import importlib.util
import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'smartsearch'))

from plezy_search import records, store  # noqa: E402
from plezy_search.common import embedding_key, sha, vector_blob  # noqa: E402
from plezy_search.indexer import Indexer  # noqa: E402

DIGEST = 'd' * 64
MODEL = {'name': 'embeddinggemma:300m', 'digest': DIGEST}


def load_pilot():
    spec = importlib.util.spec_from_file_location('pilot', ROOT / 'scripts' / 'search_index_pilot.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def series(i, name, genres=('Sci-Fi & Fantasy',), rating=8.5, overview='A crew explores space.', **extra):
    return {'Id': f'{i:032x}', 'Type': 'Series', 'Name': name, 'Overview': overview, 'Genres': list(genres),
            'CommunityRating': rating, 'ProductionYear': 2010, 'PremiereDate': '2010-01-01T00:00:00Z',
            'People': [{'Name': 'Jane Actor', 'Role': 'Captain Vale', 'Type': 'Actor'}],
            'Studios': [{'Name': 'Netflix'}], 'Tags': ['space'], **extra}


def episode(i, series_id, series_name, season, number, name, overview='Things happen.'):
    return {'Id': f'{i:032x}', 'Type': 'Episode', 'Name': name, 'SeriesId': series_id, 'SeriesName': series_name,
            'ParentIndexNumber': season, 'IndexNumber': number, 'Overview': overview, 'CommunityRating': 7.9}


def movie(i, name, **extra):
    base = {'Id': f'{i:032x}', 'Type': 'Movie', 'Name': name, 'Overview': 'A heist goes wrong.',
            'Genres': ['Crime'], 'CommunityRating': 7.1, 'ProductionYear': 1999, 'PremiereDate': '1999-05-01T00:00:00Z'}
    base.update(extra)
    return base


class FakeJellyfin:
    def __init__(self, items):
        self.items = {x['Id']: x for x in items}
        self.fail_pages = set()

    def login(self):
        return {'server_id': 'srv', 'user_id': 'usr', 'key': sha('srv:usr')}

    def page(self, kind, start, limit):
        if (kind, start) in self.fail_pages:
            from plezy_search.common import SearchError
            raise SearchError('connection failed')
        rows = sorted((x for x in self.items.values() if x['Type'] == kind), key=lambda x: x['Name'])
        return rows[start:start + limit], len(rows)

    def by_ids(self, ids):
        return [self.items[i] for i in ids if i in self.items]

    def changed_since(self, cutoff, start, limit):
        rows = sorted((x for x in self.items.values() if x.get('_changed')), key=lambda x: x['Name'])
        return rows[start:start + limit]


class FakeOllama:
    def __init__(self):
        self.calls = 0
        self.texts = 0

    def available(self):
        return True

    def embed(self, texts):
        self.calls += 1
        self.texts += len(texts)
        out = []
        for t in texts:
            h = sha(t)
            out.append(vector_blob([int(h[i % 64], 16) + 1 for i in range(768)]))
        return out, 1.0


def make_indexer(tmp, items, seed=None):
    data = Path(tmp)
    (data / 'access.json').write_text(json.dumps({'jellyfin_url': 'http://jf', 'jellyfin_username': 'u',
                                                  'jellyfin_password': 'p', 'ollama_url': 'http://ol'}))
    settings = {'model': MODEL, 'device_id': 'test', 'embed_batch': 4}
    if seed:
        settings['seed_database'] = str(seed)
    worker = Indexer(data, settings)
    worker.jf = FakeJellyfin(items)
    worker.ollama = FakeOllama()
    worker.ollama_up = True
    import plezy_search.indexer as ix
    ix.require_local_disk = lambda path: 'ext4'
    worker.open()
    return worker


class PilotCompatibility(unittest.TestCase):
    """Carried-over vectors are only valid if the embedding text is identical."""

    def test_documents_match_pilot_byte_for_byte(self):
        pilot = load_pilot()
        source = {'key': 'k'}
        samples = [movie(1, 'Heat <i>(1995)</i> &amp; more'), series(2, 'Firefly'),
                   episode(3, f'{2:032x}', 'Modern Family', 4, 1, 'Bringing Up Baby', 'Phil &amp; Jay go fishing.')]
        for raw in samples:
            mine = records.build(raw)
            theirs = pilot.record(raw, source)
            self.assertEqual(mine['document'], theirs['document'])
            self.assertEqual(embedding_key(DIGEST, mine['document']),
                             pilot.embedding_key({'model': {'digest': DIGEST}}, theirs['document']))

    def test_virtual_and_untitled_items_are_skipped(self):
        self.assertIsNone(records.build(movie(1, 'X', LocationType='Virtual')))
        self.assertIsNone(records.build(movie(1, '')))


class IndexBehaviour(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.items = [series(1, 'Firefly'), series(2, 'Friends', genres=('Comedy',), rating=8.9),
                      episode(3, f'{1:032x}', 'Firefly', 1, 1, 'Serenity'),
                      episode(4, f'{2:032x}', 'Friends', 1, 1, 'Pilot'),
                      movie(5, 'Heat'), movie(6, 'Future Film', Overview='', CommunityRating=None,
                                                PremiereDate='2099-01-01T00:00:00Z', ProductionYear=2099)]
        self.w = make_indexer(self.tmp.name, self.items)

    def tearDown(self):
        self.w.db.close()
        self.tmp.cleanup()

    def embed_all(self):
        while self.w.embed_step():
            pass

    def test_import_structured_fields_and_terms(self):
        self.assertTrue(self.w.initial_import())
        row = self.w.db.execute("SELECT rating, year, kind FROM items WHERE title='Firefly'").fetchone()
        self.assertEqual(row, (8.5, 2010, 'Series'))
        genres = {r[0] for r in self.w.db.execute("SELECT value FROM item_terms WHERE field='genre'")}
        self.assertEqual(genres, {'Sci-Fi & Fantasy', 'Comedy', 'Crime'})
        hit = self.w.db.execute("SELECT count(*) FROM search_text WHERE search_text MATCH 'vale'").fetchone()[0]
        self.assertGreaterEqual(hit, 1)  # character names are searchable

    def test_embeddings_are_reused_not_regenerated(self):
        self.w.initial_import()
        self.embed_all()
        first = self.w.ollama.texts
        self.assertEqual(first, 6)
        # replaying the whole import changes nothing and makes no new requests
        self.w.db.execute("DELETE FROM meta WHERE key='import'")
        self.w.initial_import()
        self.embed_all()
        self.assertEqual(self.w.ollama.texts, first)
        # progress-style metadata change (rating) keeps the vector
        self.w.jf.items[f'{5:032x}']['CommunityRating'] = 7.5
        self.w.put(self.w.jf.items[f'{5:032x}'])
        self.assertIsNotNone(self.w.db.execute("SELECT embedding_key FROM items WHERE title='Heat'").fetchone()[0])
        # a changed description needs exactly one new vector
        self.w.jf.items[f'{5:032x}']['Overview'] = 'A different plot.'
        self.w.put(self.w.jf.items[f'{5:032x}'])
        self.embed_all()
        self.assertEqual(self.w.ollama.texts, first + 1)

    def test_upcoming_and_missing_metadata_are_tagged_and_resolved(self):
        self.w.initial_import()
        reason = self.w.db.execute("SELECT reason, status FROM description_rechecks").fetchall()
        self.assertEqual(len(reason), 1)
        self.assertEqual(set(reason[0][0].split(',')), {'missing_description', 'upcoming', 'no_rating'})
        future = self.w.jf.items[f'{6:032x}']
        future.update(Overview='A real plot arrived.', CommunityRating=6.5, PremiereDate='2020-01-01T00:00:00Z',
                      ProductionYear=2020)
        self.w.db.execute("UPDATE description_rechecks SET next_check_utc='2000-01-01'")
        self.assertEqual(self.w.rechecks(), 1)
        self.assertEqual(self.w.db.execute("SELECT status FROM description_rechecks").fetchone()[0], 'resolved')
        self.assertEqual(self.w.db.execute("SELECT overview FROM items WHERE title='Future Film'").fetchone()[0],
                         'A real plot arrived.')

    def test_still_incomplete_items_are_rescheduled_not_dropped(self):
        self.w.initial_import()
        self.w.db.execute("UPDATE description_rechecks SET next_check_utc='2000-01-01'")
        self.w.rechecks()
        status, attempts, due = self.w.db.execute(
            'SELECT status, attempts, next_check_utc FROM description_rechecks').fetchone()
        self.assertEqual((status, attempts), ('pending', 1))
        self.assertGreater(due, '2001')

    def test_new_content_is_caught_up(self):
        self.w.initial_import()
        new = movie(9, 'Brand New', _changed=True)
        self.w.jf.items[new['Id']] = new
        self.w.catchup()
        self.assertEqual(self.w.db.execute("SELECT count(*) FROM items WHERE title='Brand New'").fetchone()[0], 1)

    def test_reconcile_hides_removed_items_only_after_complete_pass(self):
        self.w.initial_import()
        del self.w.jf.items[f'{5:032x}']
        self.w.jf.fail_pages.add(('Episode', 0))
        from plezy_search.common import SearchError
        with self.assertRaises(SearchError):
            self.w.reconcile()
        self.w.db.rollback()
        self.assertEqual(self.w.db.execute("SELECT active FROM items WHERE title='Heat'").fetchone()[0], 1)
        self.w.jf.fail_pages.clear()
        self.w.reconcile()
        self.assertEqual(self.w.db.execute("SELECT active FROM items WHERE title='Heat'").fetchone()[0], 0)
        self.assertEqual(self.w.db.execute("SELECT count(*) FROM items").fetchone()[0], 6)  # nothing deleted

    def test_events_queue_and_apply(self):
        from plezy_search.events import queue_changes
        self.w.initial_import()
        new = movie(10, 'Event Movie')
        self.w.jf.items[new['Id']] = new
        queue_changes(self.w.db, {'MessageType': 'LibraryChanged',
                                  'Data': {'ItemsAdded': [new['Id']], 'ItemsRemoved': [f'{5:032x}']}})
        self.w.apply_pending()
        self.assertEqual(self.w.db.execute("SELECT active FROM items WHERE title='Event Movie'").fetchone()[0], 1)
        self.assertEqual(self.w.db.execute("SELECT active FROM items WHERE title='Heat'").fetchone()[0], 0)


class SeedCarryOver(unittest.TestCase):
    def test_seed_vectors_are_attached_without_new_requests(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw = movie(5, 'Heat')
            doc = records.build(raw)['document']
            seed = Path(tmp) / 'seed.sqlite'
            s = sqlite3.connect(seed)
            store.connect  # schema compatible columns
            s.execute('CREATE TABLE embedding_cache(key TEXT PRIMARY KEY,content_sha256 TEXT,model_digest TEXT,'
                      'format_version TEXT,dimensions INTEGER,vector BLOB,created_utc TEXT,origin TEXT)')
            s.execute('CREATE TABLE query_cache(key TEXT,query TEXT,model_digest TEXT,vector BLOB,timing_json TEXT,created_utc TEXT)')
            s.execute('INSERT INTO embedding_cache VALUES(?,?,?,?,?,?,?,?)',
                      (embedding_key(DIGEST, doc), sha(doc), DIGEST, 'plezy-metadata-v1', 768,
                       vector_blob([1.0] * 768), 'x', 'pilot'))
            s.commit()
            s.close()
            data = Path(tmp) / 'data'
            data.mkdir()
            w = make_indexer(data, [raw], seed=seed)
            w.initial_import()
            self.assertEqual(w.embed_step(), 0)
            self.assertEqual(w.ollama.calls, 0)
            w.db.close()


if __name__ == '__main__':
    unittest.main()
