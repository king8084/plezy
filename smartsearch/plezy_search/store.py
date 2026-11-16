"""SQLite storage for the search index (lives only in the service data dir)."""

import json
import re
import sqlite3
import urllib.parse
from pathlib import Path

from . import records
from .common import FORMAT, SearchError, embedding_key, packed, plain, utc

SCHEMA_VERSION = 2
DB_NAME = 'index.sqlite'

SCHEMA = '''
CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS embedding_cache(
  key TEXT PRIMARY KEY, content_sha256 TEXT NOT NULL, model_digest TEXT NOT NULL,
  format_version TEXT NOT NULL, dimensions INTEGER NOT NULL, vector BLOB NOT NULL,
  created_utc TEXT NOT NULL, origin TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS items(
  item_id TEXT PRIMARY KEY, kind TEXT NOT NULL, title TEXT NOT NULL,
  series_id TEXT, series TEXT NOT NULL DEFAULT '', season INTEGER, episode INTEGER,
  year INTEGER, premiere TEXT, rating REAL, critic REAL, official_rating TEXT,
  runtime_min INTEGER, language TEXT, status TEXT, overview TEXT NOT NULL,
  document TEXT NOT NULL, content_sha256 TEXT NOT NULL, embedding_key TEXT,
  embed_error TEXT, description_status TEXT NOT NULL, data_json TEXT NOT NULL,
  data_sha256 TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1,
  date_created TEXT, updated_utc TEXT NOT NULL, seen_generation TEXT);
CREATE INDEX IF NOT EXISTS items_kind ON items(active, kind, rating);
CREATE INDEX IF NOT EXISTS items_series ON items(series_id, season, episode);
CREATE INDEX IF NOT EXISTS items_pending ON items(active, embedding_key, embed_error);
CREATE INDEX IF NOT EXISTS items_year ON items(kind, year);
CREATE INDEX IF NOT EXISTS items_seen ON items(seen_generation);
CREATE TABLE IF NOT EXISTS item_terms(
  item_id TEXT NOT NULL, field TEXT NOT NULL, value TEXT NOT NULL, norm TEXT NOT NULL,
  PRIMARY KEY(item_id, field, norm));
CREATE INDEX IF NOT EXISTS item_terms_lookup ON item_terms(field, norm);
CREATE VIRTUAL TABLE IF NOT EXISTS search_text USING fts5(
  title, series, people, labels, overview,
  tokenize="unicode61 remove_diacritics 2", prefix='2 3 4');
CREATE VIRTUAL TABLE IF NOT EXISTS title_trigram USING fts5(title, tokenize='trigram');
CREATE TABLE IF NOT EXISTS pending_changes(
  item_id TEXT PRIMARY KEY, action TEXT NOT NULL, seen_utc TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS description_rechecks(
  item_id TEXT PRIMARY KEY, reason TEXT NOT NULL, status TEXT NOT NULL,
  next_check_utc TEXT NOT NULL, last_checked_utc TEXT, attempts INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS query_cache(
  key TEXT PRIMARY KEY, query TEXT NOT NULL, model_digest TEXT NOT NULL,
  vector BLOB NOT NULL, timing_json TEXT NOT NULL, created_utc TEXT NOT NULL);
'''

ITEM_COLUMNS = ('item_id', 'kind', 'title', 'series_id', 'series', 'season', 'episode', 'year',
                'premiere', 'rating', 'critic', 'official_rating', 'runtime_min', 'language',
                'status', 'overview', 'document', 'content_sha256')


def connect(path, readonly=False, journal='PERSIST'):
    """PERSIST is the default because it never deletes side files (owner rule:
    nothing on Unraid is ever deleted). WAL is only for local scratch builds."""
    path = Path(path)
    if readonly:
        uri = 'file:' + urllib.parse.quote(str(path.resolve())) + '?mode=ro'
        db = sqlite3.connect(uri, uri=True, timeout=30, check_same_thread=False)
        db.execute('PRAGMA query_only=ON')
        return db
    if path.is_symlink():
        raise SearchError('database path must not be a symlink')
    db = sqlite3.connect(path, timeout=30)
    if journal not in ('PERSIST', 'WAL'):
        raise SearchError('unsupported journal mode')
    db.execute('PRAGMA journal_mode=' + journal)
    db.execute('PRAGMA synchronous=' + ('NORMAL' if journal == 'WAL' else 'FULL'))
    db.executescript(SCHEMA)
    db.execute("INSERT OR IGNORE INTO meta VALUES('schema_version', ?)", (str(SCHEMA_VERSION),))
    db.commit()
    return db


def get(db, key, default=None):
    row = db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
    return json.loads(row[0]) if row else default


def put(db, key, value):
    db.execute('INSERT INTO meta VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
               (key, packed(value)))


def bind_identity(db, source, model):
    """Refuse to mix accounts or embedding models inside one database."""
    for key, value in (('source', source), ('model', model)):
        existing = get(db, key)
        if existing is None:
            put(db, key, value)
        elif existing != value:
            raise SearchError(key + ' differs from the one this index was built with')
    db.commit()


# --- description quality (same recogniser as the pilot) -----------------------

_PLACEHOLDER = re.compile(
    r'(?:tba|tbd|to be (?:announced|added|updated|confirmed)|(?:no )?(?:overview|description|synopsis)'
    r'(?: (?:available|yet))?|plot (?:unknown|under wraps))[.!]?')


def later(days=0, minutes=0):
    import datetime as dt
    return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=days, minutes=minutes)).isoformat()


def description_status(overview):
    text = plain(overview).casefold()
    if not text:
        return 'missing'
    if re.match(r'^created by fileflows(?:\s|$)', text) or _PLACEHOLDER.fullmatch(text):
        return 'placeholder'
    return 'present'


def recheck_reasons(rec, today=None):
    """Why an item's metadata is not final yet; empty when it is complete.

    Tagged items are re-read from Jellyfin (read-only) on the daily check and
    the tag clears itself once real data arrives.
    """
    today = today or utc()[:10]
    reasons = []
    status = description_status(rec['overview'])
    if status != 'present':
        reasons.append(status + '_description')
    if rec['premiere'] and rec['premiere'] > today:
        reasons.append('upcoming')
    elif not rec['premiere'] and rec['kind'] == 'Movie' and rec['year'] and rec['year'] >= int(today[:4]):
        reasons.append('upcoming')
    if rec['kind'] in ('Movie', 'Series'):
        if rec['rating'] is None:
            reasons.append('no_rating')
        if not rec['genres']:
            reasons.append('no_genres')
    return reasons


# --- item writes ---------------------------------------------------------------

def upsert(db, rec, model_digest, generation=None):
    """Insert/update one item. Returns 'new', 'changed' or 'same'.

    Unchanged items cost one indexed read. Changed descriptions detach the old
    vector; an identical document re-attaches an existing cached vector, so a
    replayed event or progress-only change never triggers new embedding work.
    """
    row = db.execute('SELECT rowid, data_sha256 FROM items WHERE item_id=?', (rec['item_id'],)).fetchone()
    if row and row[1] == rec['data_sha256']:
        db.execute('UPDATE items SET active=1, seen_generation=coalesce(?, seen_generation) WHERE rowid=?',
                   (generation, row[0]))
        return 'same'
    ekey = embedding_key(model_digest, rec['document'])
    cached = db.execute('SELECT 1 FROM embedding_cache WHERE key=?', (ekey,)).fetchone()
    status = description_status(rec['overview'])
    values = [rec[c] for c in ITEM_COLUMNS] + [ekey if cached else None, status, packed(rec),
                                               rec['data_sha256'], rec['date_created'], utc(), generation]
    db.execute(f'''INSERT INTO items({','.join(ITEM_COLUMNS)}, embedding_key, description_status,
          data_json, data_sha256, date_created, updated_utc, seen_generation)
        VALUES({','.join('?' * (len(ITEM_COLUMNS) + 7))})
        ON CONFLICT(item_id) DO UPDATE SET {','.join(c + '=excluded.' + c for c in ITEM_COLUMNS[1:])},
          embedding_key=excluded.embedding_key, embed_error=NULL,
          description_status=excluded.description_status, data_json=excluded.data_json,
          data_sha256=excluded.data_sha256, date_created=excluded.date_created,
          updated_utc=excluded.updated_utc, active=1,
          seen_generation=coalesce(excluded.seen_generation, items.seen_generation)''', values)
    rowid = row[0] if row else db.execute('SELECT rowid FROM items WHERE item_id=?', (rec['item_id'],)).fetchone()[0]
    db.execute('DELETE FROM item_terms WHERE item_id=?', (rec['item_id'],))
    db.executemany('INSERT INTO item_terms VALUES(?,?,?,?)',
                   [(rec['item_id'],) + t for t in records.terms(rec)])
    if row:
        db.execute('DELETE FROM search_text WHERE rowid=?', (rowid,))
        db.execute('DELETE FROM title_trigram WHERE rowid=?', (rowid,))
    db.execute('INSERT INTO search_text(rowid,title,series,people,labels,overview) VALUES(?,?,?,?,?,?)',
               (rowid,) + records.text_fields(rec))
    db.execute('INSERT INTO title_trigram(rowid,title) VALUES(?,?)', (rowid, rec['title']))
    reasons = recheck_reasons(rec)
    if reasons:
        # New tags are due on the next daily pass; existing tags keep their schedule.
        db.execute('''INSERT INTO description_rechecks(item_id,reason,status,next_check_utc)
            VALUES(?,?,'pending',?) ON CONFLICT(item_id) DO UPDATE SET reason=excluded.reason, status='pending' ''',
                   (rec['item_id'], ','.join(reasons), later(days=1)))
    else:
        db.execute("UPDATE description_rechecks SET status='resolved', reason='' WHERE item_id=? AND status='pending'",
                   (rec['item_id'],))
    return 'changed' if row else 'new'


def hide(db, item_id):
    """Removal from Jellyfin becomes an inactive index row, never a deletion."""
    db.execute('UPDATE items SET active=0, updated_utc=? WHERE item_id=?', (utc(), item_id))


# --- carrying over the pilot seed --------------------------------------------

def import_seed(db, seed_path, model):
    """Copy content-addressed vectors from the pilot database (opened read-only).

    Only vectors made with the same model digest and format are taken. Items
    themselves are re-read from Jellyfin, and pick these vectors up by key.
    """
    seed_path = Path(seed_path)
    src = sqlite3.connect('file:' + urllib.parse.quote(str(seed_path.resolve())) + '?mode=ro&immutable=1', uri=True)
    try:
        rows = src.execute('SELECT key,content_sha256,model_digest,format_version,dimensions,vector,created_utc,origin '
                           'FROM embedding_cache WHERE model_digest=? AND format_version=?',
                           (model['digest'], FORMAT)).fetchall()
        queries = src.execute('SELECT key,query,model_digest,vector,timing_json,created_utc FROM query_cache '
                              'WHERE model_digest=?', (model['digest'],)).fetchall()
    finally:
        src.close()
    before = db.total_changes
    db.executemany('INSERT OR IGNORE INTO embedding_cache VALUES(?,?,?,?,?,?,?,?)', rows)
    added = db.total_changes - before
    db.executemany('INSERT OR IGNORE INTO query_cache VALUES(?,?,?,?,?,?)', queries)
    put(db, 'seed', {'path_name': seed_path.parent.name, 'vectors_offered': len(rows),
                     'vectors_added': added, 'query_vectors': len(queries), 'imported_utc': utc()})
    db.commit()
    return len(rows), added
