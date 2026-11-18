"""Search engine over the index (read-only).

instant(): titles (typo tolerant) + understood filters + full text. No AI, so it
           works when the Ollama PC is asleep. Target: a few milliseconds.
smart():   meaning-based matching with the query embedding, restricted by the
           same filters, fused with full-text ranks.
"""

import collections
import difflib
import json
import re
import threading
import time

import numpy as np

from pathlib import Path

from . import imdb_extras
from . import query as Q
from . import store
from .common import DIMENSIONS, SearchError, norm, sha, utc

QUERY_PREFIX = 'task: search result | query: '
QUERY_CACHE_FORMAT = ':search-result-v1:'   # same key formula as the pilot cache


STOPWORDS = set('''a an the of in on at to for from by with without and or but nor so as is are was were be been being
his her hers their theirs its it he she they them him we us you your our my me i this that these those who whom whose
which what when where while after before during into onto over under about against between through than then there here
up down out off again once only own same too very can will just do does did doing has have had having get gets got
s t d ll re ve not no'''.split())


def _fts_tokens(text, keep_stopwords=True):
    tokens = [t for t in re.findall(r'\w+', norm(text)) if t]
    if keep_stopwords:
        return tokens
    content = [t for t in tokens if t not in STOPWORDS]
    return content or tokens


# "gear 4" must find "Fourth Gear" / "Gear Four": a number and its words are
# one word to the search. One/first are left alone ("One Piece", "first time").
_NUMBER_WORDS = [('2', 'two', 'second', '2nd'), ('3', 'three', 'third', '3rd'), ('4', 'four', 'fourth', '4th'),
                 ('5', 'five', 'fifth', '5th'), ('6', 'six', 'sixth', '6th'), ('7', 'seven', 'seventh', '7th'),
                 ('8', 'eight', 'eighth', '8th'), ('9', 'nine', 'ninth', '9th'), ('10', 'ten', 'tenth', '10th')]
NUMBER_FORMS = {form: group for group in _NUMBER_WORDS for form in group}


def _match_expr(tokens, prefix_last=True, op=' '):
    parts = []
    for i, t in enumerate(tokens):
        forms = NUMBER_FORMS.get(t)
        if forms:
            parts.append('(' + ' OR '.join(f'"{f}"' for f in forms) + ')')
            continue
        quoted = '"' + t.replace('"', '""') + '"'
        if prefix_last and i == len(tokens) - 1 and len(t) >= 2:
            quoted += '*'
        parts.append(quoted)
    # FTS5 joins bare phrases with an implicit AND, but not bracketed groups.
    return (' AND ' if op == ' ' else op).join(parts)


FIRST_TIME = re.compile(r'\b(for the first time|first time|first use|first appearance|debuts?|debut of|origin of)\b')
_FIRST_TIME_WORDS = {'first', 'time', 'times', 'debut', 'debuts', 'appearance', 'origin', 'use', 'uses', 'used',
                     'using', 'for'}


class Engine:
    def __init__(self, db_path, ollama=None, model=None):
        self.db_path = db_path
        self.ollama = ollama
        self.model = model
        self._local = threading.local()
        self.vocab = {'people': {}}
        self.vectors = None          # (matrix, item_ids, index_by_id)
        self._vector_sig = None
        self._lock = threading.Lock()
        self.verifier = None
        self._query_vectors = collections.OrderedDict()   # small in-memory LRU
        self.refresh()

    def source_key(self):
        src = store.get(self.db, 'source')
        return sha(src['server_id'] + ':' + src['user_id'])

    # -- connections & caches ---------------------------------------------------
    @property
    def db(self):
        conn = getattr(self._local, 'db', None)
        if conn is None:
            conn = store.connect(self.db_path, readonly=True)
            self._local.db = conn
        return conn

    def refresh(self):
        """Reload vocabulary and (if changed) the vector matrix."""
        db = self.db
        people = {}
        for value, n in db.execute("SELECT value, norm FROM item_terms WHERE field='person' AND norm LIKE '% %' "
                                   "GROUP BY norm"):
            people[n] = value
        series = {}
        for item_id, title in db.execute("SELECT item_id, title FROM items WHERE kind='Series' AND active=1"):
            key = norm(title)
            if len(key) >= 3:
                series.setdefault(key, []).append(item_id)
        titles = {}
        for item_id, kind, title, year in db.execute(
                "SELECT item_id, kind, title, year FROM items WHERE active=1 AND kind IN ('Movie','Series')"):
            titles.setdefault(norm(title), []).append((item_id, kind, year))
        self.vocab = {'people': people, 'series': series, 'titles': titles}
        external = {}
        for item_id, kind, data in db.execute(
                "SELECT item_id, kind, data_json FROM items WHERE active=1 AND kind IN ('Movie','Series')"):
            try:
                ids = json.loads(data).get('provider_ids') or {}
            except ValueError:
                continue
            for provider, value in ids.items():
                provider = provider.lower()
                if provider in ('imdb', 'tmdb', 'tvdb') and value:
                    external.setdefault((kind, provider, str(value).strip().lower()), []).append(item_id)
        self.external = external
        # Directors/writers and vote counts from IMDb's datasets (Jellyfin's
        # metadata has cast only and no votes). Joined by IMDb id.
        crew, votes = {}, {}
        extras = imdb_extras.load(Path(self.db_path).parent / imdb_extras.FILE_NAME)
        for (kind, provider, value), item_ids in external.items():
            entry = extras.get(value) if provider == 'imdb' else None
            if not entry:
                continue
            for item_id in item_ids:
                if entry.get('v'):
                    votes[item_id] = entry['v']
                for name in entry.get('d', []) + entry.get('w', []):
                    n = norm(name)
                    if ' ' in n:
                        crew.setdefault(n, set()).add(item_id)
                        people.setdefault(n, name)
        self.crew = crew
        self.votes = votes
        groups = {'anime': set(), 'cartoon': set(), 'tv': set()}
        try:
            for library_id, name, collection in db.execute('SELECT library_id, name, collection_type FROM libraries'):
                n = norm(name)
                if re.search(r'\banim(e|es|ez)\b', n):
                    groups['anime'].add(library_id)
                elif re.search(r'\bcartoons?\b', n):
                    groups['cartoon'].add(library_id)
                elif collection == 'tvshows':
                    groups['tv'].add(library_id)
        except Exception:   # older index without library tagging
            pass
        self.library_groups = groups
        sig = db.execute('SELECT count(*), max(updated_utc) FROM items WHERE active=1 AND embedding_key IS NOT NULL').fetchone()
        if sig != self._vector_sig:
            rows = db.execute('SELECT i.item_id, e.vector FROM items i JOIN embedding_cache e ON e.key=i.embedding_key '
                              'WHERE i.active=1').fetchall()
            if rows:
                matrix = np.frombuffer(b''.join(r[1] for r in rows), dtype='<f4').reshape(len(rows), DIMENSIONS)
                ids = [r[0] for r in rows]
                with self._lock:
                    self.vectors = (matrix, ids, {x: n for n, x in enumerate(ids)})
            self._vector_sig = sig

    # -- filters ----------------------------------------------------------------
    ANIME_WORDS = {'anime', 'animes', 'manga', 'shounen', 'shonen', 'seinen', 'isekai', 'animated', 'animation'}
    CARTOON_WORDS = {'cartoon', 'cartoons', 'kids', 'kid', 'children', 'childrens', 'animated', 'animation'}

    def _seed_scope(self, seed_id):
        """Library scope for rows seeded by a title: a seed in an anime or
        cartoon library keeps that group (more anime after anime)."""
        groups = getattr(self, 'library_groups', {})
        seed_libraries = {r[0] for r in self.db.execute(
            'SELECT library_id FROM item_libraries WHERE item_id=?', (seed_id,))} if seed_id else set()
        allowed = {name for name, ids in groups.items() if ids & seed_libraries}
        return self._library_scope(Q.parse('', self.vocab), allow=allowed) or ('1', [])

    def _library_scope(self, p, allow=()):
        """Owner rule: anime and cartoon libraries only answer when asked for.

        Returns (sql, args) keeping items with at least one library outside the
        excluded groups (or no recorded library), or None when nothing is excluded.
        """
        words = set(norm(p.original).split())
        excluded = set()
        groups = getattr(self, 'library_groups', {})
        if not (words & self.ANIME_WORDS or 'anime' in p.genres or 'anime' in allow):
            excluded |= groups.get('anime', set())
        if not (words & self.CARTOON_WORDS or 'kids' in p.genres or 'animation' in p.genres or 'cartoon' in allow):
            excluded |= groups.get('cartoon', set())
        if not excluded:
            return None
        owner = "CASE WHEN i.kind='Episode' THEN i.series_id ELSE i.item_id END"
        marks = ','.join('?' * len(excluded))
        sql = (f"(NOT EXISTS (SELECT 1 FROM item_libraries l WHERE l.item_id={owner}) OR EXISTS "
               f"(SELECT 1 FROM item_libraries l WHERE l.item_id={owner} AND l.library_id NOT IN ({marks})))")
        return sql, sorted(excluded)

    # Searches (owner rule, Nov 18): a library word picks the libraries;
    # without one, every library answers. Home rows keep [_library_scope].
    ANIME_LIBRARY_WORDS = {'anime', 'animes'}
    CARTOON_LIBRARY_WORDS = {'cartoon', 'cartoons'}
    SHOW_LIBRARY_WORDS = {'show', 'shows', 'series', 'tv'}
    ANIME_MOVIE_SQL = ("({o} IN (SELECT item_id FROM item_terms WHERE field='genre' AND value='Animation') AND "
                       "({o} IN (SELECT item_id FROM item_terms WHERE field='tag' AND norm IN "
                       "('anime','based on manga','based on light novel','shounen','seinen','shoujo','isekai')) "
                       "OR (SELECT language FROM items o WHERE o.item_id={o})='ja'))")

    def _requested_groups(self, raw):
        """Library words in a request: anime -> the anime library, cartoon(s) ->
        Cartoons, show(s)/series/tv -> TV Shows (only without anime/cartoon)."""
        text = re.sub(r'\bshow me\b', ' ', norm(raw))
        words = set(text.split())
        groups = set()
        if words & self.ANIME_LIBRARY_WORDS:
            groups.add('anime')
        if words & self.CARTOON_LIBRARY_WORDS:
            groups.add('cartoon')
        if not groups and words & self.SHOW_LIBRARY_WORDS:
            groups.add('tv')
        return groups

    def _search_scope(self, groups):
        """(sql, args) keeping only the requested libraries, or None for all.
        Movies all live in the Movies library, so "anime"/"cartoons" keep the
        movies that are anime / animated."""
        if not groups:
            return None
        owner = "CASE WHEN i.kind='Episode' THEN i.series_id ELSE i.item_id END"
        library_groups = getattr(self, 'library_groups', {})
        libraries = sorted(set().union(*(library_groups.get(g, set()) for g in groups)))
        if not libraries:
            return None     # an index without library tagging cannot tell
        parts, args = [], []
        if libraries:
            parts.append(f"EXISTS (SELECT 1 FROM item_libraries l WHERE l.item_id={owner} AND l.library_id IN "
                         f"({','.join('?' * len(libraries))}))")
            args += libraries
        anime_movie = self.ANIME_MOVIE_SQL.format(o='i.item_id')
        if 'anime' in groups:
            parts.append(f"(i.kind='Movie' AND {anime_movie})")
        if 'cartoon' in groups:
            parts.append("(i.kind='Movie' AND i.item_id IN (SELECT item_id FROM item_terms WHERE field='genre' "
                         f"AND value='Animation') AND NOT {anime_movie})")
        if not parts:
            return '0', []
        return '(' + ' OR '.join(parts) + ')', args

    def _first_time_order(self, raw, results):
        """"luffy uses gear 4 for the first time": of the episodes that match the
        request best (title + description), the earliest comes first."""
        if not results or not FIRST_TIME.search(norm(raw)):
            return results
        episodes = [r for r in results if r.get('kind') == 'Episode']
        if len(episodes) < 2:
            return results
        ids = [r['id'] for r in episodes]
        text = {row[0]: (norm(row[1] or ''), set(norm(row[2] or '').split())) for row in self.db.execute(
            f"SELECT item_id, title || ' ' || overview, series FROM items WHERE item_id IN "
            f"({','.join('?' * len(ids))})", ids)}
        wanted = [t for t in _fts_tokens(raw, keep_stopwords=False)
                  if t not in _FIRST_TIME_WORDS and t not in self.ANIME_LIBRARY_WORDS | self.CARTOON_LIBRARY_WORDS]

        def score(r):
            body, series_words = text.get(r['id'], ('', set()))
            words = set(re.findall(r'\w+', body))
            keys = [t for t in wanted if t not in series_words]
            return sum(1 for t in keys if (NUMBER_FORMS.get(t) and words & set(NUMBER_FORMS[t])) or t in words)

        scores = {r['id']: score(r) for r in episodes}
        best = max(scores.values())
        if best < 2:
            return results
        first = sorted((r for r in episodes if scores[r['id']] == best),
                       key=lambda r: (r.get('season') or 0, r.get('episode') or 0))
        lead = {r['id'] for r in first}
        return first + [r for r in results if r['id'] not in lead]

    def _keep_requested(self, results, groups):
        """Drop results outside the requested libraries (title/show paths)."""
        scope = self._search_scope(groups)
        if not scope or not results:
            return results
        ids = [r['id'] for r in results]
        keep = {row[0] for row in self.db.execute(
            f"SELECT i.item_id FROM items i WHERE i.item_id IN ({','.join('?' * len(ids))}) AND {scope[0]}",
            ids + scope[1])}
        return [r for r in results if r['id'] in keep]

    def _filter_sql(self, p):
        """SQL WHERE for the parsed filters, applied to alias i (series via s)."""
        kinds = p.kinds or ({'Series', 'Movie'} if p.has_filters else set())
        where, args = ['i.active=1'], []
        if kinds:
            where.append('i.kind IN (%s)' % ','.join('?' * len(kinds)))
            args += sorted(kinds)
        # Episodes inherit genres/people/studios/language/status from their show.
        owner = "CASE WHEN i.kind='Episode' THEN i.series_id ELSE i.item_id END"
        requested = getattr(p, 'library_groups', set())
        for concept in p.genres:
            # The library already says what "anime"/"cartoons" means.
            if (concept == 'anime' and 'anime' in requested) or \
                    (concept in ('animation', 'kids') and 'cartoon' in requested):
                continue
            if concept == 'anime':
                where.append(f"{owner} IN (SELECT item_id FROM item_terms WHERE field='genre' AND value='Animation')")
                where.append(f"({owner} IN (SELECT item_id FROM item_terms WHERE field='tag' AND norm IN "
                             f"('anime','based on manga','based on light novel','shounen','seinen','shoujo','isekai')) "
                             f"OR (SELECT language FROM items o WHERE o.item_id={owner})='ja')")
                continue
            clauses = []
            for kind in sorted(kinds or {'Series', 'Movie', 'Episode'}):
                names = Q.genre_names(concept, 'Movie' if kind == 'Movie' else 'Series')
                tags = Q.tag_fallback(concept) if kind != 'Movie' else set()
                if names:
                    clauses.append(f"(i.kind=? AND {owner} IN (SELECT item_id FROM item_terms WHERE field='genre' "
                                   f"AND value IN ({','.join('?' * len(names))})))")
                    args += [kind] + sorted(names)
                if tags:
                    clauses.append(f"(i.kind=? AND {owner} IN (SELECT item_id FROM item_terms WHERE field='tag' "
                                   f"AND norm IN ({','.join('?' * len(tags))})))")
                    args += [kind] + sorted(norm(t) for t in tags)
            where.append('(' + (' OR '.join(clauses) or '0') + ')')
        if p.rating_min is not None:
            where.append('i.rating >= ?')
            args.append(p.rating_min)
        if p.rating_max is not None:
            where.append('i.rating < ?')
            args.append(p.rating_max)
        if p.year_min:
            where.append('i.year >= ?')
            args.append(p.year_min)
        if p.year_max:
            where.append('i.year <= ?')
            args.append(p.year_max)
        if p.runtime_max:
            where.append('i.runtime_min <= ?')
            args.append(p.runtime_max)
        if p.runtime_min:
            where.append('i.runtime_min >= ?')
            args.append(p.runtime_min)
        if p.languages:
            where.append(f"(SELECT language FROM items o WHERE o.item_id={owner}) IN ({','.join('?' * len(p.languages))})")
            args += sorted(p.languages)
        if p.status:
            where.append(f"(SELECT status FROM items o WHERE o.item_id={owner}) = ?")
            args.append(p.status)
        for studios in p.studios:
            where.append(f"{owner} IN (SELECT item_id FROM item_terms WHERE field='studio' AND norm IN "
                         f"({','.join('?' * len(studios))}))")
            args += studios
        for person in p.people:
            crew = sorted(getattr(self, 'crew', {}).get(person, ()))
            if crew:
                where.append(f"({owner} IN (SELECT item_id FROM item_terms WHERE field='person' AND norm=?) "
                             f"OR {owner} IN ({','.join('?' * len(crew))}))")
                args += [person, *crew]
            else:
                where.append(f"{owner} IN (SELECT item_id FROM item_terms WHERE field='person' AND norm=?)")
                args.append(person)
        scope = self._search_scope(getattr(p, 'library_groups', set()))
        if scope:
            where.append(scope[0])
            args += scope[1]
        return ' AND '.join(where), args

    def _order(self, p):
        if p.sort == 'newest':
            return 'i.year DESC NULLS LAST, i.rating DESC NULLS LAST'
        if p.sort == 'oldest':
            return 'i.year ASC NULLS LAST, i.rating DESC NULLS LAST'
        return 'i.rating DESC NULLS LAST, i.year DESC NULLS LAST'

    # -- result shaping ---------------------------------------------------------
    COLUMNS = 'i.item_id, i.kind, i.title, i.year, i.rating, i.series, i.series_id, i.season, i.episode, i.runtime_min, i.critic'

    def _row(self, r, reason, score=None):
        out = {'id': r[0], 'kind': r[1], 'title': r[2], 'year': r[3], 'rating': r[4], 'reason': reason}
        votes = getattr(self, 'votes', {}).get(r[0])
        if votes:
            out['votes'] = votes
        if r[1] == 'Episode':
            out.update(series=r[5], series_id=r[6], season=r[7], episode=r[8])
        if r[9]:
            out['runtime_min'] = r[9]
        if r[10] is not None:
            out['critic'] = r[10]
        if score is not None:
            out['score'] = round(float(score), 4)
        return out

    def _with_libraries(self, results):
        """Attach library ids (episodes inherit their show's) so the app can honour hidden libraries."""
        if not results:
            return results
        owners = {r['id']: r.get('series_id') or r['id'] for r in results}
        ids = sorted(set(owners.values()) | {x for r in results for x in r.get('other_ids', [])})
        libs = {}
        for item_id, library_id in self.db.execute(
                f"SELECT item_id, library_id FROM item_libraries WHERE item_id IN ({','.join('?' * len(ids))})", ids):
            libs.setdefault(item_id, []).append(library_id)
        for r in results:
            r['libraries'] = sorted(libs.get(owners[r['id']], []))
            if r.get('other_ids'):
                r['copies'] = [{'id': x, 'libraries': sorted(libs.get(x, []))} for x in r['other_ids']]
        return results

    # -- ranking helpers ----------------------------------------------------------
    FLAVOUR = {
        'scifi': {'science fiction', 'sci fi', 'hard sci fi', 'space', 'space opera', 'space travel', 'spaceship',
                  'spacecraft', 'space station', 'space colony', 'space battle', 'alien', 'alien invasion',
                  'extraterrestrial', 'time travel', 'time loop', 'dystopia', 'post apocalyptic future', 'future',
                  'futuristic', 'robot', 'android', 'cyborg', 'artificial intelligence', 'artificial intelligence a i',
                  'cyberpunk', 'mad scientist', 'experiment', 'multiple dimensions', 'parallel world',
                  'parallel universe', 'clone', 'virtual reality', 'mecha', 'planet mars', 'genetic engineering',
                  'simulation', 'apocalypse', 'scientist'},
        'fantasy': {'magic', 'dragon', 'fantasy world', 'dark fantasy', 'elves', 'isekai', 'sword and sorcery',
                    'wizard', 'witch', 'fantasy', 'high fantasy', 'mythology', 'fairy tale', 'sorcery',
                    'urban fantasy', 'kingdom', 'king', 'medieval'},
    }

    def _flavour_rank(self, rows, concepts):
        """TV lumps sci-fi and fantasy together; use keywords to put the asked-for one first."""
        wanted = [c for c in concepts if c in self.FLAVOUR]
        if not wanted or not rows:
            return rows
        other = 'fantasy' if wanted[0] == 'scifi' else 'scifi'
        ids = [r[0] for r in rows]
        tags = {}
        for item_id, n in self.db.execute(f"SELECT item_id, norm FROM item_terms WHERE field='tag' AND item_id IN "
                                          f"({','.join('?' * len(ids))})", ids):
            tags.setdefault(item_id, set()).add(n)

        def tier(r):
            t = tags.get(r[0], set())
            if r[1] == 'Movie' or t & self.FLAVOUR[wanted[0]]:
                return 0
            return 2 if t & self.FLAVOUR[other] else 1
        return sorted(rows, key=tier)   # stable: keeps rating order inside a tier

    @staticmethod
    def _dedupe(results):
        """Several copies of one movie (e.g. 1080p + 4K) become one result."""
        out, index = [], {}
        for r in results:
            key = (r['kind'], norm(r['title']), r.get('year'), r.get('series_id'), r.get('season'), r.get('episode'))
            if key in index:
                out[index[key]].setdefault('other_ids', []).append(r['id'])
                continue
            index[key] = len(out)
            out.append(r)
        return out

    CUES_AFTER = {'episode', 'episodes', 'ep', 'season', 'seasons', 'show', 'series', 'sitcom'}

    def _series_in(self, p):
        """Find a show the request explicitly points at ("the friends episode where ...").

        Many show titles are ordinary words (FROM, Trapped, Hidden, War...), so a
        title with fewer than two content words only counts when followed by a cue
        such as "episode"/"season"/"show", or after "episode of".
        """
        words = norm(p.original).split()
        series = self.vocab.get('series', {})
        for size in range(min(6, len(words)), 0, -1):
            for i in range(len(words) - size + 1):
                chunk = ' '.join(words[i:i + size])
                if chunk not in series:
                    continue
                content = [w for w in chunk.split() if w not in STOPWORDS]
                after = words[i + size] if i + size < len(words) else ''
                before = ' '.join(words[max(0, i - 2):i])
                cued = after in self.CUES_AFTER or before.endswith(('episode of', 'episode in', 'episodes of'))
                if len(content) >= 2 or (content and cued):
                    return chunk, series[chunk], words[:i] + words[i + size:]
        return None

    def _soft_genre_boost(self, fused, concepts):
        ids = list(fused)
        rows = self.db.execute(
            f"SELECT i.item_id, i.kind, t.field, t.value, t.norm FROM items i JOIN item_terms t ON "
            f"t.item_id=CASE WHEN i.kind='Episode' THEN i.series_id ELSE i.item_id END "
            f"WHERE i.item_id IN ({','.join('?' * len(ids))}) AND t.field IN ('genre','tag')", ids).fetchall()
        hits = set()
        for item_id, kind, field, value, n in rows:
            for c in concepts:
                names = Q.genre_names(c, 'Movie' if kind == 'Movie' else 'Series')
                tags = Q.tag_fallback(c) | ({'anime', 'based on manga', 'shounen', 'seinen'} if c == 'anime' else set())
                if (field == 'genre' and value in names and c != 'anime') or (field == 'tag' and n in tags):
                    hits.add(item_id)
        for item_id in hits:
            fused[item_id] *= 1.3

    def _recall(self, raw, restrict):
        """Map generator-suggested titles onto items in this library (exact title match)."""
        found = []
        for s in self.verifier.suggest(raw):
            title = norm(s.get('title', ''))
            if not title:
                continue
            if s.get('type') == 'episode' and s.get('show'):
                show_ids = self.vocab.get('series', {}).get(norm(s['show']), [])
                if not show_ids:
                    continue
                marks = ','.join('?' * len(show_ids))
                rows = [r[0] for r in self.db.execute(
                    f"SELECT item_id, title FROM items WHERE kind='Episode' AND active=1 AND series_id IN ({marks})",
                    show_ids).fetchall() if norm(r[1]) == title or norm(r[1]).rstrip(' 0123456789') == title]
                if not rows and isinstance(s.get('season'), int) and isinstance(s.get('episode'), int):
                    rows = [r[0] for r in self.db.execute(
                        f"SELECT item_id FROM items WHERE kind='Episode' AND active=1 AND series_id IN ({marks}) "
                        f"AND season=? AND episode=?", show_ids + [s['season'], s['episode']])]
            else:
                kind = 'Movie' if s.get('type') == 'movie' else 'Series'
                rows = [r for r in self.vocab.get('titles', {}).get(title, []) if r[1] == kind]
                year = s.get('year')
                if isinstance(year, int) and len(rows) > 1:
                    rows = sorted(rows, key=lambda r: abs((r[2] or year) - year))
                rows = [r[0] for r in rows]
            for item_id in rows[:2]:
                if item_id not in found:
                    found.append(item_id)
        if restrict and found:
            where, args = restrict
            ok = {r[0] for r in self.db.execute(
                f"SELECT i.item_id FROM items i WHERE {where} AND i.item_id IN ({','.join('?' * len(found))})",
                args + found)}
            found = [x for x in found if x in ok]
        return found

    # -- title matching -----------------------------------------------------------
    def _titles(self, raw, limit=12):
        tokens = _fts_tokens(raw)
        if not tokens:
            return []
        rows = self.db.execute(
            f'SELECT {self.COLUMNS}, bm25(search_text, 10.0, 4.0, 0, 0, 0) AS score FROM search_text '
            f'JOIN items i ON i.rowid=search_text.rowid WHERE search_text MATCH ? AND i.active=1 '
            f"ORDER BY (i.kind='Episode'), score LIMIT ?",
            ('{title series} : (' + _match_expr(tokens) + ')', limit * 4)).fetchall()
        wanted = norm(raw)
        scored = []
        for r in rows:
            t = norm(r[2])
            exact = t == wanted or (r[1] == 'Episode' and False)
            starts = t.startswith(wanted)
            if r[1] == 'Episode' and norm(r[5]).startswith(wanted):
                continue            # the show itself is returned; skip its episodes here
            scored.append((0 if exact else 1 if starts else 2, r[1] == 'Episode', r[11], r))
        scored.sort(key=lambda x: x[:3])
        return [self._row(r, 'title') for *_, r in scored[:limit]]

    def _fuzzy_titles(self, raw, limit=8):
        """Typos: candidates by shared trigrams, then edit-similarity."""
        wanted = norm(raw)
        if len(wanted) < 4:
            return []
        grams = {wanted[i:i + 3] for i in range(len(wanted) - 2) if ' ' not in wanted[i:i + 3]}
        if not grams:
            return []
        expr = ' OR '.join('"' + g.replace('"', '""') + '"' for g in sorted(grams))
        rows = self.db.execute(
            f'SELECT {self.COLUMNS} FROM title_trigram JOIN items i ON i.rowid=title_trigram.rowid '
            f"WHERE title_trigram MATCH ? AND i.active=1 AND i.kind!='Episode' ORDER BY rank LIMIT 300",
            (expr,)).fetchall()
        scored = []
        for r in rows:
            t = norm(r[2])
            ratio = max(difflib.SequenceMatcher(None, wanted, t).ratio(),
                        difflib.SequenceMatcher(None, wanted, t[:len(wanted) + 2]).ratio())
            if ratio >= 0.72:
                scored.append((-ratio, -(r[4] or 0), r))
        scored.sort(key=lambda x: x[:2])
        return [self._row(r, 'similar title', -s) for s, _, r in scored[:limit]]

    # -- instant ------------------------------------------------------------------
    UNLOCK_LABELS = {'anime': 'Anime', 'cartoon': 'Cartoons'}

    def _unlock(self, raw):
        """("anime conan forest") -> ({'anime'}, 'conan forest'): the words that
        open the anime/cartoon libraries, and the request without them."""
        words = norm(raw).split()
        unlocked, rest = set(), []
        for w in words:
            hit = False
            if w in self.ANIME_LIBRARY_WORDS:
                unlocked.add('anime')
                hit = True
            if w in self.CARTOON_LIBRARY_WORDS:
                unlocked.add('cartoon')
                hit = True
            if not hit:
                rest.append(w)
        return unlocked, ' '.join(rest)

    def instant(self, raw, limit=40):
        """Owner rule: anime/cartoon libraries open only when asked ("anime",
        "animes", "cartoon(s)"). When that word just opens the library for a
        request that names something ("anime conan forest", "cartoon spongebob
        jellyfish"), the rest is searched as usual, episodes included, with the
        library open. A request that is only a category ("anime comedies", "90s
        cartoons") keeps the category listing."""
        unlocked, rest = self._unlock(raw)
        groups = self._requested_groups(raw)
        if unlocked and rest and not Q.parse(rest, self.vocab).has_filters:
            out = self._instant(rest, limit, groups=groups)
            labels = [self.UNLOCK_LABELS[u] for u in sorted(unlocked)]
            out.update(query=raw, understood=labels + [u for u in out['understood'] if u not in labels])
            return out
        return self._instant(raw, limit, groups=groups)

    def _instant(self, raw, limit=40, groups=None):
        start = time.perf_counter()
        p = Q.parse(raw, self.vocab)
        p.library_groups = self._requested_groups(raw) if groups is None else groups
        results, seen = [], set()

        def add(rows):
            for r in rows:
                if r['id'] not in seen:
                    seen.add(r['id'])
                    results.append(r)

        titles = self._titles(raw) if len(norm(raw).split()) <= 8 else []
        strong = [t for t in titles if norm(t['title']).startswith(norm(raw)) or norm(raw) in norm(t['title'])]
        add(strong)
        exact_title = any(norm(t['title']) == norm(raw) for t in strong)
        if exact_title:
            p.has_filters_overridden = True
        scoped = None if exact_title else self._series_in(p)
        if scoped and [w for w in scoped[2] if w not in Q.FILLER and w not in ('episode', 'episodes', 'ep', 'where', 'when')]:
            # "<show> episode where ..." -> that show's episodes ranked by the remaining words
            chunk, series_ids, rest = scoped
            words = [w for w in rest if w not in Q.FILLER and w not in ('episode', 'episodes', 'ep', 'where', 'when')]
            rows = self.db.execute(
                f'SELECT {self.COLUMNS} FROM search_text JOIN items i ON i.rowid=search_text.rowid '
                f"WHERE search_text MATCH ? AND i.active=1 AND i.kind='Episode' AND i.series_id IN "
                f"({','.join('?' * len(series_ids))}) ORDER BY bm25(search_text, 4.0, 0, 2.0, 0, 1.0) LIMIT ?",
                [_match_expr(words, prefix_last=False, op=' OR ')] + series_ids + [limit]).fetchall()
            add(self._row(r, 'episode text') for r in rows)
        if p.has_filters and not exact_title:
            where, args = self._filter_sql(p)
            text_tokens = _fts_tokens(p.text)
            if text_tokens:
                # Rank filtered items that also match the leftover words first.
                rows = self.db.execute(
                    f'SELECT {self.COLUMNS} FROM items i JOIN search_text ON search_text.rowid=i.rowid '
                    f'WHERE search_text MATCH ? AND {where} ORDER BY bm25(search_text, 6.0, 3.0, 2.0, 2.0, 1.0) LIMIT ?',
                    [_match_expr(text_tokens, op=' OR ')] + args + [limit]).fetchall()
                add(self._row(r, 'filters + text') for r in rows)
            rows = self.db.execute(f'SELECT {self.COLUMNS} FROM items i WHERE {where} ORDER BY {self._order(p)} LIMIT ?',
                                   args + [limit * 4]).fetchall()
            add(self._row(r, 'filters') for r in self._flavour_rank(rows, p.genres))
        if not strong and not scoped and not p.has_filters and len(norm(raw).split()) <= 5:
            # Possible misspelt title ("brekaing bad"): close matches beat loose word hits.
            add(self._fuzzy_titles(raw))
        add(titles)
        if len(results) < limit and (not p.has_filters or exact_title):
            tokens = _fts_tokens(raw, keep_stopwords=len(norm(raw).split()) <= 4)
            scope_sql, scope_args = self._search_scope(p.library_groups) or ('1', [])
            if tokens:
                rows = self.db.execute(
                    f'SELECT {self.COLUMNS} FROM search_text JOIN items i ON i.rowid=search_text.rowid '
                    f'WHERE search_text MATCH ? AND i.active=1 AND {scope_sql} '
                    f'ORDER BY bm25(search_text, 8.0, 4.0, 3.0, 2.0, 1.0) LIMIT ?',
                    [_match_expr(tokens)] + scope_args + [limit]).fetchall()
                add(self._row(r, 'text') for r in rows)
                words = _fts_tokens(p.text, keep_stopwords=False)[:8]
                if len(results) < 5 and len(words) > 1:
                    rows = self.db.execute(
                        f'SELECT {self.COLUMNS} FROM search_text JOIN items i ON i.rowid=search_text.rowid '
                        f'WHERE search_text MATCH ? AND i.active=1 AND {scope_sql} '
                        f'ORDER BY bm25(search_text, 8.0, 4.0, 3.0, 2.0, 1.0) LIMIT ?',
                        [_match_expr(words, prefix_last=False, op=' OR ')] + scope_args + [limit]).fetchall()
                    add(self._row(r, 'some words') for r in rows)
        return {'query': raw, 'understood': p.understood, 'filters': p.has_filters, 'unwatched': p.unwatched,
                'results': self._with_libraries(self._dedupe(self._first_time_order(
                    raw, self._keep_requested(results, p.library_groups)))[:limit]),
                'indexed_libraries': [r[0] for r in self.db.execute('SELECT library_id FROM libraries')], 'took_ms': round((time.perf_counter() - start) * 1000, 2)}

    # -- Home rows ------------------------------------------------------------------
    def top_rated(self, kinds=('Movie', 'Series'), min_rating=7.5, limit=80):
        """Highest IMDb-rated movies/shows (the app removes ones the viewer watched)."""
        p = Q.parse('', self.vocab)
        scope_sql, scope_args = self._library_scope(p) or ('1', [])
        rows = self.db.execute(
            f"SELECT {self.COLUMNS} FROM items i WHERE i.active=1 AND i.kind IN ({','.join('?' * len(kinds))}) "
            f"AND i.rating >= ? AND {scope_sql} ORDER BY i.rating DESC, i.year DESC LIMIT ?",
            list(kinds) + [min_rating] + scope_args + [limit * 2]).fetchall()
        results = self._dedupe([self._row(r, 'top rated') for r in rows])[:limit]
        return {'results': self._with_libraries(results)}

    def similar(self, item_id, limit=40):
        """Titles closest in meaning to [item_id] (an episode counts as its show)."""
        if self.vectors is None:
            raise SearchError('index has no embeddings yet')
        row = self.db.execute('SELECT item_id, kind, series_id FROM items WHERE item_id=?', (item_id,)).fetchone()
        if not row:
            return {'source': None, 'results': []}
        source_id = row[2] if row[1] == 'Episode' and row[2] else row[0]
        source = self.db.execute(f'SELECT {self.COLUMNS} FROM items i WHERE i.item_id=?', (source_id,)).fetchone()
        matrix, ids, index = self.vectors
        if source is None or source_id not in index:
            return {'source': None, 'results': []}
        kind = source[1]
        scores = matrix @ matrix[index[source_id]]
        scope_sql, scope_args = self._seed_scope(source_id)
        allowed = {r[0] for r in self.db.execute(
            f'SELECT i.item_id FROM items i WHERE i.active=1 AND i.kind=? AND {scope_sql}', [kind] + scope_args)}
        picked = []
        for n in np.argsort(-scores):
            candidate = ids[n]
            if candidate == source_id or candidate not in allowed:
                continue
            picked.append(candidate)
            if len(picked) >= limit * 2:
                break
        rows = {r[0]: r for r in self.db.execute(
            f"SELECT {self.COLUMNS} FROM items i WHERE i.item_id IN ({','.join('?' * len(picked))})", picked)}
        results = self._dedupe([self._row(rows[i], 'similar') for i in picked if i in rows])[:limit]
        return {'source': self._row(source, 'source'), 'results': self._with_libraries(results)}

    def resolve(self, refs, seed=None, limit=60):
        """Library titles for outside recommendations, in the given order.

        [refs] are "movie|show:imdb|tmdb|tvdb:value" strings (Simkl, Trakt) or
        "item:<id>" for Jellyfin's own suggestions. Unknown titles are skipped;
        the app shows only what the library has.
        """
        kinds = {'movie': 'Movie', 'show': 'Series'}
        wanted = []
        for ref in refs:
            if ref.startswith('item:'):
                if ref[5:] and ref[5:] not in wanted:
                    wanted.append(ref[5:])
                continue
            parts = ref.split(':', 2)
            if len(parts) != 3 or parts[0] not in kinds or parts[1] not in ('imdb', 'tmdb', 'tvdb'):
                continue
            for item_id in self.external.get((kinds[parts[0]], parts[1], parts[2].strip().lower()), []):
                if item_id not in wanted:
                    wanted.append(item_id)
        if not wanted:
            return {'results': []}
        seed_id = None
        if seed:
            row = self.db.execute('SELECT item_id, kind, series_id FROM items WHERE item_id=?', (seed,)).fetchone()
            if row:
                seed_id = row[2] if row[1] == 'Episode' and row[2] else row[0]
        scope_sql, scope_args = self._seed_scope(seed_id)
        rows = {r[0]: r for r in self.db.execute(
            f"SELECT {self.COLUMNS} FROM items i WHERE i.active=1 AND i.kind IN ('Movie','Series') "
            f"AND i.item_id IN ({','.join('?' * len(wanted))}) AND {scope_sql}", wanted + scope_args)}
        results = self._dedupe([self._row(rows[i], 'recommended') for i in wanted
                                if i in rows and i != seed_id])[:limit]
        return {'results': self._with_libraries(results)}

    # -- smart --------------------------------------------------------------------
    def query_vector(self, text):
        key = sha(self.model['digest'] + QUERY_CACHE_FORMAT + text)
        with self._lock:
            hit = self._query_vectors.get(key)
            if hit is not None:
                self._query_vectors.move_to_end(key)
                return hit, True
        row = self.db.execute('SELECT vector FROM query_cache WHERE key=?', (key,)).fetchone()
        if row:
            return np.frombuffer(row[0], dtype='<f4'), True
        if not self.ollama:
            raise SearchError('AI search unavailable')
        # Keep the small (~0.6 GB) embedding model loaded between searches so the
        # AI row stays snappy; it unloads itself after 4 idle hours.
        blobs, _ = self.ollama.embed([QUERY_PREFIX + text], timeout=10, keep_alive='4h')
        vector = np.frombuffer(blobs[0], dtype='<f4')
        with self._lock:
            self._query_vectors[key] = vector
            while len(self._query_vectors) > 2000:
                self._query_vectors.popitem(last=False)
        return vector, False

    def smart(self, raw, limit=20, verify=True, verify_top=8, confirm=False, recall=True, series=None):
        """Meaning-based search. [series] (a show's item id) searches only that
        show's episodes: the show's "Find" box ("phil basketball" inside Modern Family)."""
        start = time.perf_counter()
        if self.vectors is None:
            raise SearchError('index has no embeddings yet')
        forced = None
        if series:
            row = self.db.execute("SELECT title FROM items WHERE item_id=? AND kind='Series'", (series,)).fetchone()
            if not row:
                return {'query': raw, 'understood': [], 'results': [], 'unwatched': False}
            forced = (norm(row[0]), [series])
            # Read as "<show> episode <request>" so the checker and the language
            # model know which show the characters belong to.
            raw = f'{row[0]} episode {raw}'
        p = Q.parse(raw, self.vocab)
        p.library_groups = set() if forced else self._requested_groups(raw)
        # Embed the whole request: words the parser turns into filters ("tv show",
        # "anime") still carry meaning. Filters are applied separately below.
        scoped = self._series_in(p)
        if forced:
            scoped = (forced[0], forced[1], norm(raw).split())
        text = raw
        vec, cached = self.query_vector(text)
        t_embed = time.perf_counter()
        matrix, ids, index = self.vectors
        scores = matrix @ vec
        restrict = None
        if forced or (scoped and len(scoped[2]) >= 2):
            # A show named inside a descriptive request: search its episodes.
            restrict = ("i.kind='Episode' AND i.active=1 AND i.series_id IN (%s)" % ','.join('?' * len(scoped[1])),
                        scoped[1])
        elif p.has_filters:
            restrict = self._filter_sql(p)
        else:
            scope = self._search_scope(p.library_groups)
            if scope:
                restrict = ('i.active=1 AND ' + scope[0], scope[1])
        if restrict:
            where, args = restrict
            allowed = [index[r[0]] for r in self.db.execute(f'SELECT i.item_id FROM items i WHERE {where}', args)
                       if r[0] in index]
            mask = np.full(len(ids), -np.inf, dtype='<f4')
            mask[allowed] = 0
            scores = scores + mask
        top = np.argsort(-scores)[:max(limit * 3, 60)]
        semantic = [(ids[n], float(scores[n])) for n in top if np.isfinite(scores[n])]
        # Reciprocal-rank fusion of meaning, the instant results (titles, filters,
        # show-scoped text) and full text, so exact words and titles still count.
        fused = {}
        for rank, (item_id, _) in enumerate(semantic):
            fused[item_id] = fused.get(item_id, 0) + 1 / (60 + rank)
        instant = self.instant(raw, 30)['results']
        if forced:
            instant = [r for r in instant if r.get('series_id') in forced[1]]
        for rank, r in enumerate(instant):
            fused[r['id']] = fused.get(r['id'], 0) + 1 / (60 + rank)
        tokens = _fts_tokens(text)
        if tokens:
            where, args = restrict or ('i.active=1', [])
            for rank, (item_id,) in enumerate(self.db.execute(
                    f'SELECT i.item_id FROM search_text JOIN items i ON i.rowid=search_text.rowid '
                    f'WHERE search_text MATCH ? AND {where} ORDER BY bm25(search_text, 6.0, 3.0, 2.0, 1.0, 2.0) LIMIT 60',
                    [_match_expr(tokens, prefix_last=False, op=' OR ')] + args)):
                fused[item_id] = fused.get(item_id, 0) + 0.5 / (60 + rank)
        # Genre hints from a description nudge matching items up ("space anime ...").
        if p.soft_genres and fused:
            self._soft_genre_boost(fused, p.soft_genres)
        # The generator's own knowledge of famous plots ("a boy sees dead people").
        recalled = []
        if recall and self.verifier:
            recalled = self._recall(raw, restrict)
            for rank, item_id in enumerate(recalled):
                fused[item_id] = fused.get(item_id, 0) + 2 / (60 + rank)
        wants_episode = bool(scoped) or bool({'episode', 'episodes', 'ep', 'season'} & set(norm(raw).split())) \
            or p.kinds == {'Episode'}
        if not wants_episode:
            # "show about ...", "anime about ...": whole shows/movies first.
            kinds = dict(self.db.execute(f"SELECT item_id, kind FROM items WHERE item_id IN "
                                         f"({','.join('?' * len(fused))})", list(fused)))
            for item_id in fused:
                if kinds.get(item_id) == 'Episode':
                    fused[item_id] *= 0.6
        order = sorted(fused, key=lambda x: -fused[x])
        if forced:
            in_show = {r[0] for r in self.db.execute(
                f"SELECT item_id FROM items WHERE kind='Episode' AND series_id IN "
                f"({','.join('?' * len(forced[1]))})", forced[1])}
            order = [x for x in order if x in in_show]
        if p.library_groups:
            kept = {r['id'] for r in self._keep_requested([{'id': x} for x in order], p.library_groups)}
            order = [x for x in order if x in kept]
        order = order[:limit]
        sim = dict(semantic)
        rows = {r[0]: r for r in self.db.execute(
            f'SELECT {self.COLUMNS} FROM items i WHERE i.item_id IN ({",".join("?" * len(order))})', order)}
        results = []
        for item_id in order:
            if item_id in rows:
                out = self._row(rows[item_id], 'meaning', fused[item_id])
                if item_id in sim:
                    out['similarity'] = round(sim[item_id], 4)
                results.append(out)
        checked_ms = None
        if verify and self.verifier and results and (scoped or len(p.text.split()) >= 3):
            # Scene-style requests: check the top few against their descriptions and
            # re-rank: confirmed > possible (by support) > rejected identity mismatches.
            t0 = time.perf_counter()
            top = results[:verify_top]
            verdicts = self.verifier.check(raw, [r['id'] for r in top], use_generator=confirm,
                                           shows=[scoped[0]] if scoped else [])
            rank = {'confirmed': 0, 'possible': 1, 'rejected': 2}
            for r in top:
                v = verdicts.get(r['id'], {'status': 'possible', 'reason': 'not_checked'})
                r['match'] = v['status'] if v['status'] in rank else 'possible'
                r['support'] = v.get('entailment')
                if r['match'] != 'rejected' and v.get('evidence'):
                    r['evidence'] = v['evidence'][0]
            # Blend: the checker's support decides when it is confident; the
            # original (meaning + text) order only breaks ties when it is unsure.
            # An episode/movie title repeating 2+ of the request's key words is
            # strong evidence too ("friends episode where rachel quits" -> "...Rachel Quits").
            show_words = set(scoped[0].split()) if scoped else set()
            key_words = {w for w in _fts_tokens(raw, keep_stopwords=False)
                         if w not in Q.FILLER and w not in self.CUES_AFTER and w not in show_words
                         and w not in ('where', 'when', 'give')}
            for n, r in enumerate(top):
                support = r.get('support') or 0
                prior = 0.35 * (1 - n / len(top)) * (1 - support)
                title_hits = len(key_words & set(_fts_tokens(r['title'])))
                bonus = (0.3 if title_hits >= 2 else 0) + (0.25 if r['id'] in recalled else 0)
                r['_key'] = (rank[r['match']], -(support + prior + bonus))
            top.sort(key=lambda r: r.pop('_key'))
            results = top + results[verify_top:]
            checked_ms = round((time.perf_counter() - t0) * 1000, 1)
        for r in results:
            if r['id'] in recalled:
                r['recalled'] = True
        results = self._with_libraries(results)
        return {'query': raw, 'understood': p.understood, 'results': results, 'query_vector_cached': cached,
                'unwatched': p.unwatched,
                'verify_ms': checked_ms,
                'embed_ms': round((t_embed - start) * 1000, 1),
                'took_ms': round((time.perf_counter() - start) * 1000, 1)}
