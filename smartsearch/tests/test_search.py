import datetime as dt
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from plezy_search.query import parse  # noqa: E402
from plezy_search.search import Engine  # noqa: E402
from test_index import MODEL, FakeOllama, episode, make_indexer, movie, series  # noqa: E402

TODAY = dt.date(2026, 11, 16)


class ParserTest(unittest.TestCase):
    def test_owner_example_rating_genre_kind(self):
        p = parse('give me sci fi shows with over 8 ratings', today=TODAY)
        self.assertEqual((p.kinds, p.genres, p.rating_min > 8, p.text), ({'Series'}, ['scifi'], True, ''))

    def test_rating_phrasings(self):
        self.assertEqual(parse('anime rated 8+', today=TODAY).rating_min, 8.0)
        self.assertEqual(parse('shows with imdb at least 8.5', today=TODAY).rating_min, 8.5)
        self.assertIsNone(parse('movies over 90 minutes', today=TODAY).rating_min)
        self.assertEqual(parse('movies over 90 minutes', today=TODAY).runtime_min, 90)

    def test_decades_and_years(self):
        p = parse('90s comedies', today=TODAY)
        self.assertEqual((p.year_min, p.year_max), (1990, 1999))
        self.assertEqual(parse('movies after 2010', today=TODAY).year_min, 2011)
        self.assertEqual(parse('2010s thrillers', today=TODAY).year_min, 2010)

    def test_people_need_vocabulary(self):
        p = parse('tom hanks movies', {'people': {'tom hanks': 'Tom Hanks'}}, today=TODAY)
        self.assertEqual((p.people, p.kinds), (['tom hanks'], {'Movie'}))

    def test_plot_descriptions_do_not_become_filters(self):
        p = parse('A Russian cop teams up with a Chicago detective to capture a drug lord', today=TODAY)
        self.assertEqual((p.genres, p.languages), ([], set()))
        self.assertIn('mystery', p.soft_genres)

    def test_anime_is_not_a_hard_language_filter(self):
        p = parse('anime rated 8+', today=TODAY)
        self.assertEqual((p.genres, p.languages), (['anime'], set()))

    def test_genre_words_in_a_plot_stay_hints_even_with_a_kind(self):
        p = parse('korean movie about a poor family who con their way into a rich home', today=TODAY)
        self.assertEqual((p.kinds, p.languages, p.genres), ({'Movie'}, {'ko'}, []))
        self.assertIn('family', p.soft_genres)

    def test_unwatched_phrases(self):
        for q in ('sci fi shows i haven\'t watched', 'unwatched sci fi shows', 'sci fi shows not seen yet',
                  'new to me sci fi shows'):
            p = parse(q, today=TODAY)
            self.assertTrue(p.unwatched, q)
            self.assertEqual((p.kinds, p.genres), ({'Series'}, ['scifi']), q)
        self.assertFalse(parse('watched it twice', today=TODAY).unwatched)

    def test_show_me_is_not_the_word_show(self):
        p = parse('show me funny movies', today=TODAY)
        self.assertEqual((p.kinds, p.genres), ({'Movie'}, ['comedy']))
        self.assertEqual(parse('funny shows', today=TODAY).kinds, {'Series'})

    def test_list_style_requests_keep_filters(self):
        p = parse('best korean thriller movies', today=TODAY)
        self.assertEqual((p.languages, p.genres, p.sort), ({'ko'}, ['thriller'], 'rating'))


class EngineTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        items = [
            series(1, 'Firefly', rating=9.0, Tags=['space', 'spaceship']),
            series(2, 'Dragon Saga', rating=9.1, Tags=['dragon', 'magic']),
            series(3, 'Low Rated Space', rating=6.0, Tags=['space']),
            series(4, 'Friends', genres=('Comedy',), rating=8.9),
            series(5, 'Modern Family', genres=('Comedy', 'Family'), rating=8.5),
            episode(10, f'{4:032x}', 'Friends', 7, 13, 'The One Where Rosita Dies',
                    "Rachel accidentally breaks Joey's armchair."),
            movie(20, 'Breaking Bad Movie Night', CommunityRating=7.0),
            movie(21, 'Family Fun Film', Genres=['Family'], CommunityRating=6.0),
            movie(22, 'Heat'), movie(23, 'Heat'),   # two copies of one film
        ]
        w = make_indexer(cls.tmp.name, items)
        w.initial_import()
        w.db.close()
        cls.engine = Engine(Path(cls.tmp.name) / 'index.sqlite')

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def titles(self, q):
        return [r['title'] for r in self.engine.instant(q)['results']]

    def test_scifi_shows_over_8_puts_scifi_before_fantasy_and_respects_rating(self):
        got = self.titles('sci fi shows over 8')
        self.assertEqual(got[:2], ['Firefly', 'Dragon Saga'])
        self.assertNotIn('Low Rated Space', got)

    def test_exact_title_beats_genre_words(self):
        got = self.titles('modern family')
        self.assertEqual(got[0], 'Modern Family')
        self.assertNotIn('Family Fun Film', got)

    def test_typo_finds_title(self):
        self.assertEqual(self.titles('firefli')[0], 'Firefly')

    def test_show_scoped_episode_text(self):
        got = self.engine.instant('friends episode where rachel breaks joey armchair')['results']
        self.assertEqual(got[0]['title'], 'The One Where Rosita Dies')

    def test_one_word_show_names_need_a_cue(self):
        p = parse('a woman returns from being lost at sea', self.engine.vocab, today=TODAY)
        self.assertIsNone(self.engine._series_in(p))   # 'friends' etc. not mentioned; no cue
        p = parse('the friends episode where joey breaks the chair', self.engine.vocab, today=TODAY)
        self.assertEqual(self.engine._series_in(p)[0], 'friends')

    def test_recall_maps_only_titles_in_the_library(self):
        class Stub:
            def suggest(self, q):
                return [{'type': 'movie', 'title': 'Not In Library'}, {'type': 'show', 'title': 'Firefly'},
                        {'type': 'episode', 'title': 'The One Where Rosita Dies', 'show': 'Friends'}]
        self.engine.verifier = Stub()
        try:
            got = self.engine._recall('anything', None)
        finally:
            self.engine.verifier = None
        titles = [self.engine.db.execute('SELECT title FROM items WHERE item_id=?', (i,)).fetchone()[0] for i in got]
        self.assertEqual(titles, ['Firefly', 'The One Where Rosita Dies'])

    def test_duplicate_copies_are_merged(self):
        got = self.engine.instant('heat')['results']
        heat = [r for r in got if r['title'] == 'Heat']
        self.assertEqual(len(heat), 1)
        self.assertEqual(len(heat[0]['other_ids']), 1)


if __name__ == '__main__':
    unittest.main()


class LibraryScopeTest(unittest.TestCase):
    """Owner rule: anime/cartoon libraries answer only when asked for (titles always)."""

    def test_anime_library_needs_the_word_anime(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = [series(1, 'Firefly', rating=9.0, Tags=['space']),
                     series(2, 'Galaxy Blades', genres=('Sci-Fi & Fantasy', 'Animation'), rating=9.5, Tags=['space', 'anime'])]
            w = make_indexer(tmp, items)
            w.initial_import()
            w.db.execute("INSERT INTO libraries VALUES('lib-tv','TV Shows','tvshows',NULL)")
            w.db.execute("INSERT INTO libraries VALUES('lib-anime','Animez-TV Shows','tvshows',NULL)")
            w.db.executemany('INSERT INTO item_libraries VALUES(?,?)',
                             [(f'{1:032x}', 'lib-tv'), (f'{2:032x}', 'lib-anime')])
            w.db.commit()
            w.db.close()
            engine = Engine(Path(tmp) / 'index.sqlite')

            def titles(q):
                return [r['title'] for r in engine.instant(q)['results']]

            self.assertEqual(titles('sci fi shows over 8'), ['Firefly'])
            self.assertIn('Galaxy Blades', titles('sci fi anime over 8'))
            self.assertEqual(titles('galaxy blades')[0], 'Galaxy Blades')   # titles are never hidden


class HomeRowsTest(unittest.TestCase):
    def test_top_rated_and_similar(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = [series(1, 'Firefly', rating=9.0, overview='A crew of smugglers flies a spaceship.'),
                     series(2, 'Space Crew', rating=8.0, overview='A crew of smugglers flies a spaceship too.'),
                     series(3, 'Kitchen Show', genres=('Reality',), rating=8.5, overview='Chefs cook dinner.'),
                     movie(4, 'Low Film', CommunityRating=5.0)]
            w = make_indexer(tmp, items)
            w.initial_import()
            while w.embed_step():
                pass
            w.db.close()
            engine = Engine(Path(tmp) / 'index.sqlite')
            top = [r['title'] for r in engine.top_rated(min_rating=7.5)['results']]
            self.assertEqual(top, ['Firefly', 'Kitchen Show', 'Space Crew'])
            similar = engine.similar(f'{1:032x}')
            self.assertEqual(similar['source']['title'], 'Firefly')
            self.assertNotIn('Firefly', [r['title'] for r in similar['results']])
            self.assertTrue(all(r['kind'] == 'Series' for r in similar['results']))


class ResolveTest(unittest.TestCase):
    """Simkl/Trakt recommendations map to library titles by external id."""

    def test_external_ids_map_to_library_items_in_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            items = [series(1, 'Breaking Bad', ProviderIds={'Imdb': 'tt0903747', 'Tmdb': '1396'}),
                     series(2, 'Better Call Saul', ProviderIds={'Imdb': 'tt3032476', 'Tvdb': '273181'}),
                     movie(3, 'El Camino', ProviderIds={'Tmdb': '559969'}),
                     series(4, 'Galaxy Blades', ProviderIds={'Imdb': 'tt9999999'})]
            w = make_indexer(tmp, items)
            w.initial_import()
            w.db.execute("INSERT INTO libraries VALUES('lib-anime','Anime','tvshows',NULL)")
            w.db.execute('INSERT INTO item_libraries VALUES(?,?)', (f'{4:032x}', 'lib-anime'))
            w.db.commit()
            w.db.close()
            engine = Engine(Path(tmp) / 'index.sqlite')
            refs = ['movie:tmdb:559969', 'show:tvdb:273181', 'show:imdb:tt0000001', 'show:tmdb:559969',
                    'show:imdb:TT0903747', 'show:imdb:tt9999999', 'bogus']
            got = engine.resolve(refs, seed=f'{1:032x}')['results']
            # Order kept, unknown/mismatched kinds skipped, the seed itself and the
            # anime library (seed is not anime) left out.
            self.assertEqual([r['title'] for r in got], ['El Camino', 'Better Call Saul'])
            anime_seed = engine.resolve(['show:imdb:tt9999999', 'show:imdb:tt0903747'], seed=f'{4:032x}')
            self.assertEqual([r['title'] for r in anime_seed['results']], ['Breaking Bad'])
            self.assertEqual(engine.resolve(['show:imdb:tt9999999'])['results'], [])
            jellyfin_ids = engine.resolve([f'item:{2:032x}', 'item:unknown', f'item:{4:032x}'], seed=f'{1:032x}')
            self.assertEqual([r['title'] for r in jellyfin_ids['results']], ['Better Call Saul'])


class FindInShowTest(unittest.TestCase):
    """The show page's Find box: only that show's episodes."""

    def test_series_scope_returns_only_its_episodes(self):
        with tempfile.TemporaryDirectory() as tmp:
            mf, other = f'{1:032x}', f'{2:032x}'
            items = [series(1, 'Modern Family', genres=('Comedy',)),
                     series(2, 'Hoop Dreams Show', genres=('Comedy',)),
                     episode(10, mf, 'Modern Family', 4, 8, 'Party Crasher', overview='Phil plays basketball with Luke.'),
                     episode(11, mf, 'Modern Family', 2, 3, 'Dinner Date', overview='Claire plans a dinner.'),
                     episode(12, other, 'Hoop Dreams Show', 1, 1, 'Basketball', overview='Phil plays basketball.')]
            w = make_indexer(tmp, items)
            w.initial_import()
            while w.embed_step():
                pass
            w.db.close()
            class QueryOllama(FakeOllama):
                def embed(self, texts, **_):
                    return super().embed(texts)

            engine = Engine(Path(tmp) / 'index.sqlite', QueryOllama(), MODEL)
            got = engine.smart('phil basketball', series=mf, verify=False, recall=False)['results']
            self.assertTrue(got)
            self.assertTrue(all(r['kind'] == 'Episode' and r['series_id'] == mf for r in got))
            self.assertEqual(got[0]['title'], 'Party Crasher')
            self.assertEqual(engine.smart('phil', series='missing', verify=False, recall=False)['results'], [])



class ImdbExtrasTest(unittest.TestCase):
    """Directors and vote counts come from IMDb's datasets, joined by IMDb id."""

    def test_director_search_and_votes(self):
        import gzip
        from plezy_search import imdb_extras
        with tempfile.TemporaryDirectory() as tmp:
            data = Path(tmp) / 'imdb'
            data.mkdir()

            def tsv(name, rows):
                with gzip.open(data / name, 'wt', encoding='utf-8') as f:
                    f.write('\n'.join('\t'.join(r) for r in rows) + '\n')
            tsv('title.crew.tsv.gz', [('tconst', 'directors', 'writers'),
                                      ('tt1375666', 'nm0634240', 'nm0634240'), ('tt0000001', 'nm1', '\\N')])
            tsv('name.basics.tsv.gz', [('nconst', 'primaryName'), ('nm0634240', 'Christopher Nolan'), ('nm1', 'X Y')])
            tsv('title.ratings.tsv.gz', [('tconst', 'averageRating', 'numVotes'), ('tt1375666', '8.8', '2890807')])
            items = [movie(1, 'Inception', ProviderIds={'Imdb': 'tt1375666'}, CommunityRating=8.8),
                     movie(2, 'Other Film', ProviderIds={'Imdb': 'tt7777777'}, CommunityRating=7.0)]
            w = make_indexer(tmp, items)
            w.initial_import()
            w.db.close()
            count = imdb_extras.build(data, ['tt1375666', 'tt7777777'], Path(tmp) / imdb_extras.FILE_NAME)
            self.assertEqual(count, 1)
            engine = Engine(Path(tmp) / 'index.sqlite')
            got = engine.instant('christopher nolan')['results']
            self.assertEqual([r['title'] for r in got], ['Inception'])
            self.assertEqual(got[0]['votes'], 2890807)

    def test_missing_file_changes_nothing(self):
        from plezy_search import imdb_extras
        self.assertEqual(imdb_extras.load('/nonexistent/imdb_extras.json'), {})


class UnlockedEpisodesTest(unittest.TestCase):
    """"anime"/"cartoon" open their library; named requests then return episodes too."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        items = [series(1, 'Firefly', rating=9.0, Tags=['space']),
                 series(2, 'Galaxy Blades', genres=('Animation', 'Comedy'), rating=8.5, Tags=['anime']),
                 episode(10, f'{2:032x}', 'Galaxy Blades', 1, 5, 'Episode 5',
                         'Kenji and the crew get lost deep in a haunted forest.'),
                 series(3, 'Sea Sponge', genres=('Animation', 'Comedy'), rating=8.0),
                 episode(11, f'{3:032x}', 'Sea Sponge', 1, 2, 'Jelly Day', 'The sponge goes jellyfishing all day.')]
        w = make_indexer(self.tmp.name, items)
        w.initial_import()
        w.db.execute("INSERT INTO libraries VALUES('lib-tv','TV Shows','tvshows',NULL)")
        w.db.execute("INSERT INTO libraries VALUES('lib-anime','Animez-TV Shows','tvshows',NULL)")
        w.db.execute("INSERT INTO libraries VALUES('lib-cartoon','Cartoons','tvshows',NULL)")
        w.db.executemany('INSERT INTO item_libraries VALUES(?,?)', [
            (f'{1:032x}', 'lib-tv'), (f'{2:032x}', 'lib-anime'), (f'{10:032x}', 'lib-anime'),
            (f'{3:032x}', 'lib-cartoon'), (f'{11:032x}', 'lib-cartoon')])
        w.db.commit()
        w.db.close()
        self.engine = Engine(Path(self.tmp.name) / 'index.sqlite')

    def tearDown(self):
        self.tmp.cleanup()

    def kinds_titles(self, q):
        return [(r['kind'], r['title']) for r in self.engine.instant(q)['results']]

    def test_anime_word_returns_episodes_found_by_description(self):
        for q in ('anime galaxy forest', 'animes galaxy forest', 'galaxy forest anime'):
            self.assertIn(('Episode', 'Episode 5'), self.kinds_titles(q), q)
        self.assertIn('Anime', self.engine.instant('anime galaxy forest')['understood'])

    def test_without_a_library_word_every_library_answers(self):
        self.assertIn(('Episode', 'Episode 5'), self.kinds_titles('galaxy forest'))
        self.assertIn(('Episode', 'Jelly Day'), self.kinds_titles('sponge jellyfishing'))

    def test_a_library_word_returns_only_that_library(self):
        anime = self.kinds_titles('anime forest')
        self.assertIn(('Episode', 'Episode 5'), anime)
        self.assertNotIn(('Episode', 'Jelly Day'), self.kinds_titles('anime jellyfishing'))
        self.assertNotIn(('Episode', 'Episode 5'), self.kinds_titles('cartoon forest'))
        self.assertNotIn(('Series', 'Galaxy Blades'), self.kinds_titles('shows galaxy'))
        self.assertIn(('Series', 'Firefly'), self.kinds_titles('shows firefly'))

    def test_cartoon_word_returns_cartoon_episodes(self):
        for q in ('cartoon sponge jellyfishing', 'cartoons sponge jellyfishing'):
            self.assertIn(('Episode', 'Jelly Day'), self.kinds_titles(q), q)

    def test_category_requests_keep_the_category_listing(self):
        got = self.kinds_titles('anime comedies')
        self.assertIn(('Series', 'Galaxy Blades'), got)
        self.assertNotIn(('Series', 'Firefly'), got)
