"""Always-on index writer.

Loop: initial import -> live events + catch-up -> daily rechecks of incomplete
metadata -> embeddings -> daily reconciliation. Everything is resumable from
checkpoints stored in the database. Writes happen only inside DATA_DIR.

Usage: python3 -m plezy_search.indexer DATA_DIR [--exit-when-idle]
"""

import argparse
import collections
import datetime as dt
import json
import os
import signal
import sqlite3
import sys
import threading
import time
from pathlib import Path

from . import records, store
from .clients import Jellyfin, Ollama
from .common import FORMAT, DIMENSIONS, SearchError, embedding_key, require_local_disk, save_json, sha, utc

PAGE = 100
RECHECK_BATCH = 50
CATCHUP_SECONDS = 60
RECHECK_SECONDS = 600
RECONCILE_HOURS = 24
OVERLAP_MINUTES = 5


def _ago(iso, **delta):
    return (dt.datetime.fromisoformat(iso) - dt.timedelta(**delta)).isoformat()


class Indexer:
    def __init__(self, data_dir, settings):
        self.data = Path(data_dir).resolve()
        self.settings = settings
        access_path = Path(settings.get('access_file', 'access.json'))
        access = json.loads((access_path if access_path.is_absolute() else self.data / access_path).read_text())
        self.model = settings['model']
        self.jf = Jellyfin(access, settings['device_id'])
        self.ollama = Ollama(access, self.model)
        self.batch = int(settings.get('embed_batch', 64))
        self.max_items = int(settings.get('max_items', 150_000))
        self.stopping = False
        self.db = None
        self.series_names = {}
        self.ollama_up = None
        self.last_error = None
        self.phase = 'starting'
        self.rate = collections.deque(maxlen=50)
        self._last_status = 0
        self.events = None

    # -- setup ------------------------------------------------------------------
    def open(self):
        require_local_disk(self.data)
        source = self.jf.login()
        self.db = store.connect(self.data / store.DB_NAME, journal=self.settings.get('journal_mode', 'PERSIST'))
        store.bind_identity(self.db, {'server_id': source['server_id'], 'user_id': source['user_id']}, self.model)
        seed = self.settings.get('seed_database')
        if seed and store.get(self.db, 'seed') is None:
            offered, added = store.import_seed(self.db, seed, self.model)
            print(json.dumps({'seed_vectors_offered': offered, 'seed_vectors_added': added}), flush=True)
        self.series_names = dict(self.db.execute("SELECT item_id, title FROM items WHERE kind='Series'"))

    # -- writes -----------------------------------------------------------------
    def put(self, raw, generation=None):
        rec = records.build(raw, self.series_names)
        if rec is None:
            return None
        result = store.upsert(self.db, rec, self.model['digest'], generation)
        if rec['kind'] == 'Series':
            self.series_names[rec['item_id']] = rec['title']
        return result

    def sweep(self, name):
        """Full inventory pass, checkpointed per page. Returns True when complete."""
        state = store.get(self.db, name) or {'generation': utc(), 'started': utc(), 'kind': 0, 'offset': 0,
                                             'totals': {}, 'skipped': {}}
        if state.get('done'):
            return True
        while state['kind'] < len(records.KINDS) and not self.stopping:
            kind = records.KINDS[state['kind']]
            rows, total = self.jf.page(kind, state['offset'], PAGE)
            state['totals'][kind] = total
            if sum(state['totals'].values()) > self.max_items:
                raise SearchError('library is larger than the configured safety limit')
            for raw in rows:
                if raw.get('Type') == kind and self.put(raw, state['generation']) is None:
                    state['skipped'][kind] = state['skipped'].get(kind, 0) + 1
            state['offset'] += len(rows)
            if not rows or state['offset'] >= total:
                state['kind'] += 1
                state['offset'] = 0
            store.put(self.db, name, state)
            self.db.commit()
            self.drain_events()
            self.status('importing' if name == 'import' else 'reconciling')
        if self.stopping:
            return False
        state['done'] = True
        state['finished'] = utc()
        store.put(self.db, name, state)
        self.db.commit()
        return True

    def initial_import(self):
        if not self.sweep('import'):
            return False
        if store.get(self.db, 'sync_cutoff') is None:
            state = store.get(self.db, 'import')
            store.put(self.db, 'sync_cutoff', _ago(state['started'], minutes=OVERLAP_MINUTES))
            store.put(self.db, 'last_reconcile', state['finished'])
            self.db.commit()
        return True

    def reconcile(self):
        """Daily: re-read everything; hide items Jellyfin no longer shows.

        Only a complete pass may hide anything, and only items not touched
        since the pass began. Hiding is an index flag, never a deletion.
        """
        if not self.sweep('reconcile'):
            return
        state = store.get(self.db, 'reconcile')
        seen = dict(self.db.execute('SELECT kind, count(*) FROM items WHERE seen_generation=? GROUP BY kind',
                                    (state['generation'],)))
        complete = all(seen.get(k, 0) + state['skipped'].get(k, 0) >= state['totals'].get(k, 0) for k in records.KINDS)
        hidden = 0
        if complete:
            hidden = self.db.execute('UPDATE items SET active=0 WHERE active=1 AND (seen_generation IS NULL OR seen_generation!=?) '
                                     'AND updated_utc<?', (state['generation'], state['started'])).rowcount
        store.put(self.db, 'last_reconcile', utc())
        store.put(self.db, 'last_reconcile_result', {'complete': complete, 'hidden': hidden, 'seen': seen,
                                                     'totals': state['totals'], 'finished': utc()})
        self.db.execute("DELETE FROM meta WHERE key='reconcile'")  # our own checkpoint row
        self.db.commit()

    def catchup(self):
        """Pick up anything saved in Jellyfin since the last successful pass."""
        cutoff = store.get(self.db, 'sync_cutoff')
        if cutoff is None:
            return
        started = utc()
        offset = 0
        while not self.stopping:
            rows = self.jf.changed_since(_ago(cutoff, minutes=OVERLAP_MINUTES), offset, PAGE)
            for raw in rows:
                self.put(raw)
            self.db.commit()
            offset += len(rows)
            if len(rows) < PAGE:
                break
        if not self.stopping:
            store.put(self.db, 'sync_cutoff', started)
            store.put(self.db, 'last_catchup', started)
            self.db.commit()

    def apply_pending(self):
        rows = self.db.execute('SELECT item_id, action, seen_utc FROM pending_changes ORDER BY seen_utc LIMIT 200').fetchall()
        if not rows:
            return
        for item_id, action, _ in rows:
            if action == 'hide':
                store.hide(self.db, item_id)
        wanted = [r[0] for r in rows if r[1] == 'upsert']
        for i in range(0, len(wanted), 50):
            for raw in self.jf.by_ids(wanted[i:i + 50]):
                self.put(raw)
        self.db.executemany('DELETE FROM pending_changes WHERE item_id=? AND seen_utc=?',
                            [(r[0], r[2]) for r in rows])  # our own queue rows
        self.db.commit()

    def rechecks(self):
        """Daily re-read of items with missing/placeholder/upcoming metadata."""
        due = [r[0] for r in self.db.execute(
            "SELECT q.item_id FROM description_rechecks q JOIN items i ON i.item_id=q.item_id "
            "WHERE q.status='pending' AND i.active=1 AND q.next_check_utc<=? LIMIT ?", (utc(), RECHECK_BATCH))]
        if not due:
            return 0
        found = {raw['Id']: raw for raw in self.jf.by_ids(due)}
        for item_id in due:
            raw = found.get(item_id)
            rec = records.build(raw, self.series_names) if raw else None
            if rec:
                store.upsert(self.db, rec, self.model['digest'])
                reasons = store.recheck_reasons(rec)
            else:
                reasons = ['not_returned']
            if reasons:
                attempts = self.db.execute('SELECT attempts FROM description_rechecks WHERE item_id=?', (item_id,)).fetchone()[0]
                self.db.execute("UPDATE description_rechecks SET status='pending', reason=?, attempts=attempts+1, "
                                "last_checked_utc=?, next_check_utc=? WHERE item_id=?",
                                (','.join(reasons), utc(), store.later(days=1 if attempts < 30 else 7), item_id))
            else:
                self.db.execute("UPDATE description_rechecks SET status='resolved', reason='', attempts=attempts+1, "
                                "last_checked_utc=? WHERE item_id=?", (utc(), item_id))
        self.db.commit()
        return len(due)

    # -- embeddings -------------------------------------------------------------
    def embed_step(self):
        rows = self.db.execute('SELECT item_id, document, content_sha256 FROM items WHERE active=1 '
                               'AND embedding_key IS NULL AND embed_error IS NULL LIMIT ?', (self.batch,)).fetchall()
        if not rows:
            return 0
        started = time.monotonic()
        digest = self.model['digest']
        todo = {}
        for _, document, _ in rows:
            key = embedding_key(digest, document)
            if not self.db.execute('SELECT 1 FROM embedding_cache WHERE key=?', (key,)).fetchone():
                todo[key] = document
        if todo:
            try:
                blobs, _ = self.ollama.embed(list(todo.values()))
                made = list(zip(todo.items(), blobs))
            except SearchError as error:
                if 'connection' in str(error):
                    raise
                made = self._embed_individually(todo)
            self.db.executemany('INSERT OR IGNORE INTO embedding_cache VALUES(?,?,?,?,?,?,?,?)', [
                (key, sha(doc), digest, FORMAT, DIMENSIONS, blob, utc(), 'full-index')
                for (key, doc), blob in made])
        for item_id, document, content in rows:
            key = embedding_key(digest, document)
            if self.db.execute('SELECT 1 FROM embedding_cache WHERE key=?', (key,)).fetchone():
                self.db.execute('UPDATE items SET embedding_key=? WHERE item_id=? AND content_sha256=?', (key, item_id, content))
        self.db.commit()
        self.rate.append((len(rows), time.monotonic() - started))
        return len(rows)

    def _embed_individually(self, todo):
        made = []
        for key, doc in todo.items():
            try:
                made.append(((key, doc), self.ollama.embed([doc])[0][0]))
            except SearchError as error:
                if 'connection' in str(error):
                    raise
                self.db.execute('UPDATE items SET embed_error=? WHERE document=? AND embedding_key IS NULL',
                                (str(error)[:200], doc))
        return made

    # -- snapshots & status -----------------------------------------------------
    def snapshot(self, label):
        folder = self.data / 'snapshots'
        folder.mkdir(mode=0o700, exist_ok=True)
        name = f'index-{label}-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}.sqlite'
        path = folder / name
        if path.exists():
            raise SearchError('snapshot already exists')
        dest = sqlite3.connect(path)
        self.db.backup(dest)
        dest.execute('PRAGMA journal_mode=DELETE')
        ok = dest.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        dest.close()
        if not ok:
            raise SearchError('snapshot integrity check failed')
        receipt = {'file': name, 'bytes': path.stat().st_size, 'created_utc': utc(), 'label': label}
        save_json(folder / (name + '.json'), receipt)
        store.put(self.db, 'last_snapshot', receipt)
        self.db.commit()
        return receipt

    def status(self, phase=None, force=False):
        if phase:
            self.phase = phase
        if not force and time.monotonic() - self._last_status < 3:
            return
        self._last_status = time.monotonic()
        db = self.db
        kinds = dict(db.execute('SELECT kind, count(*) FROM items WHERE active=1 GROUP BY kind'))
        total, embedded = db.execute('SELECT count(*), count(embedding_key) FROM items WHERE active=1').fetchone()
        failed = db.execute('SELECT count(*) FROM items WHERE active=1 AND embed_error IS NOT NULL').fetchone()[0]
        n = sum(x for x, _ in self.rate)
        secs = sum(y for _, y in self.rate)
        speed = n / secs if secs else None
        reasons = collections.Counter()
        for (reason,) in db.execute("SELECT reason FROM description_rechecks WHERE status='pending'"):
            reasons.update(reason.split(','))
        imp = store.get(db, 'import') or {}
        data = {
            'updated_utc': utc(), 'phase': self.phase, 'pid': os.getpid(),
            'items': kinds, 'total_items': total, 'embedded': embedded,
            'pending_embeddings': total - embedded - failed, 'embedding_failures': failed,
            'items_per_second': round(speed, 1) if speed else None,
            'eta_minutes': round((total - embedded - failed) / speed / 60, 1) if speed else None,
            'library_totals': imp.get('totals'), 'import_done': bool(imp.get('done')),
            'rechecks_pending': dict(reasons), 'ollama_available': self.ollama_up,
            'events_connected': bool(self.events and self.events.connected),
            'last_catchup': store.get(db, 'last_catchup'), 'last_reconcile': store.get(db, 'last_reconcile'),
            'last_snapshot': store.get(db, 'last_snapshot'), 'last_error': self.last_error,
        }
        save_json(self.data / 'status.json', data)

    # -- events -----------------------------------------------------------------
    def drain_events(self):
        if self.events:
            self.events.flush_into(self.db)

    def start_events(self):
        try:
            import websockets  # noqa: F401
            from .events import EventListener
        except ImportError:
            print(json.dumps({'events': 'websockets package unavailable; relying on catch-up'}), flush=True)
            return
        self.events = EventListener(lambda: self.jf.socket_url(self.settings['device_id']))
        threading.Thread(target=self.events.run_forever, name='events', daemon=True).start()

    # -- main loop --------------------------------------------------------------
    def check_ollama(self):
        try:
            self.ollama_up = self.ollama.available()
        except SearchError as error:
            self.ollama_up = False
            self.last_error = str(error)

    def run(self, exit_when_idle=False, events=True):
        self.open()
        if events:
            self.start_events()
        self.check_ollama()
        timers = collections.defaultdict(float)
        last_login = time.monotonic()
        while not self.stopping:
            try:
                if not self.initial_import():
                    continue
                now = time.monotonic()
                self.drain_events()
                if self.events and self.events.take_reconnect():
                    timers['catchup'] = 0
                self.apply_pending()
                if now - timers['catchup'] > CATCHUP_SECONDS:
                    self.catchup()
                    timers['catchup'] = now
                if now - timers['recheck'] > RECHECK_SECONDS:
                    while self.rechecks() == RECHECK_BATCH and not self.stopping:
                        pass
                    timers['recheck'] = now
                last = store.get(self.db, 'last_reconcile')
                if last and dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(last) > dt.timedelta(hours=RECONCILE_HOURS):
                    self.reconcile()
                if not self.ollama_up and now - timers['ollama'] > 60:
                    self.check_ollama()
                    timers['ollama'] = now
                worked = self.embed_step() if self.ollama_up else 0
                if worked:
                    self.status('embedding')
                else:
                    if not store.get(self.db, 'initial_snapshot') and self.ollama_up:
                        receipt = self.snapshot('initial-complete')
                        store.put(self.db, 'initial_snapshot', receipt)
                        self.db.commit()
                        self.status('up_to_date', force=True)
                        if exit_when_idle:
                            break
                    self.status('up_to_date' if self.ollama_up else 'waiting_for_ollama')
                    if exit_when_idle and store.get(self.db, 'initial_snapshot'):
                        break
                    time.sleep(2)
                if time.monotonic() - last_login > 1800:
                    self.jf.login()
                    last_login = time.monotonic()
                self.last_error = None
            except SearchError as error:
                self.db.rollback()
                self.last_error = str(error)
                if 'connection' in str(error):
                    self.check_ollama()
                self.status('retrying', force=True)
                self._sleep(15)
            except sqlite3.Error as error:
                self.db.rollback()
                self.last_error = 'database: ' + type(error).__name__
                self.status('retrying', force=True)
                self._sleep(15)
        self.status('stopped', force=True)
        self.db.close()

    def _sleep(self, seconds):
        end = time.monotonic() + seconds
        while time.monotonic() < end and not self.stopping:
            time.sleep(0.5)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('data_dir', type=Path)
    parser.add_argument('--exit-when-idle', action='store_true', help='stop after the initial index is complete')
    parser.add_argument('--no-events', action='store_true')
    parser.add_argument('--settings', type=Path, help='defaults to DATA_DIR/settings.json')
    args = parser.parse_args(argv)
    os.umask(0o077)
    settings = json.loads((args.settings or args.data_dir / 'settings.json').read_text())
    worker = Indexer(args.data_dir, settings)

    def stop(*_):
        worker.stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    worker.run(exit_when_idle=args.exit_when_idle, events=not args.no_events)


if __name__ == '__main__':
    try:
        main()
    except SearchError as error:
        print(json.dumps({'ok': False, 'error': str(error)}), flush=True)
        sys.exit(1)
