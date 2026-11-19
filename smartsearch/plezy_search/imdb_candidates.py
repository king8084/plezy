"""A fresh shortlist for "Ask AI", from IMDb's daily public datasets.

The language model only knows titles up to its training date. For list
requests ("best sci fi shows in the last 20 years") the service hands it a
shortlist of matching titles from IMDb's current data (type, year, genres,
rating, votes), including releases from last month, to rank alongside what it
knows. Built once a day by [refresh] into the service's own folder; nothing
outside it is read or written.

File: {"version": 1, "built_utc": ..., "titles": [[kind, title, year, [genres], rating, votes], ...]}
"""

import gzip
import json
import math
import os
import time
import urllib.error
import urllib.request
from pathlib import Path

FILE_NAME = 'imdb_candidates.json'
STATUS_NAME = 'imdb_candidates_status.json'
VERSION = 1
MIN_VOTES = 1000
KINDS = {'movie': 'movie', 'tvMovie': 'movie', 'tvSeries': 'show', 'tvMiniSeries': 'show'}
DATASETS = 'https://datasets.imdbws.com/'

# Request concepts (query.py) -> IMDb genre names.
GENRES = {'scifi': {'Sci-Fi'}, 'animation': {'Animation'}, 'comedy': {'Comedy'}, 'action': {'Action'},
          'thriller': {'Thriller'}, 'horror': {'Horror'}, 'drama': {'Drama'}, 'crime': {'Crime'},
          'mystery': {'Mystery'}, 'romance': {'Romance'}, 'documentary': {'Documentary'},
          'fantasy': {'Fantasy'}, 'war': {'War'}, 'western': {'Western'}, 'family': {'Family'},
          'kids': {'Family', 'Animation'}, 'music': {'Music', 'Musical'}, 'sport': {'Sport'},
          'history': {'History'}, 'adventure': {'Adventure'}, 'reality': {'Reality-TV'}}


def _rows(path):
    with gzip.open(path, 'rt', encoding='utf-8') as f:
        f.readline()
        for line in f:
            yield line.rstrip('\n').split('\t')


def build(basics_gz, ratings_gz, out_path):
    """Join IMDb's title.basics and title.ratings into the compact shortlist file."""
    ratings = {}
    for p in _rows(ratings_gz):
        try:
            votes = int(p[2])
        except (IndexError, ValueError):
            continue
        if votes >= MIN_VOTES:
            ratings[p[0]] = (float(p[1]), votes)
    titles = []
    for p in _rows(basics_gz):
        if len(p) < 9 or p[0] not in ratings or p[4] == '1':
            continue
        kind = KINDS.get(p[1])
        if not kind or not p[5].isdigit():
            continue
        rating, votes = ratings[p[0]]
        titles.append([kind, p[2], int(p[5]), [] if p[8] == '\\N' else p[8].split(','), rating, votes])
    out_path = Path(out_path)
    tmp = out_path.with_name('.' + out_path.name + '.tmp')
    tmp.write_text(json.dumps({'version': VERSION, 'built_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                               'source': 'IMDb non-commercial datasets', 'titles': titles},
                              separators=(',', ':')), encoding='utf-8')
    tmp.replace(out_path)
    return len(titles), ratings


def load(path):
    try:
        doc = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return []
    return doc.get('titles', []) if doc.get('version') == VERSION else []


def shortlist(titles, kinds=None, year_min=None, year_max=None, genres=(), limit=40, this_year=None):
    """The best-known matches for the request's own conditions, plus the most
    voted recent ones (the titles a model trained earlier cannot know)."""
    want = {'Series': 'show', 'Movie': 'movie'}.get(next(iter(kinds))) if kinds and len(kinds) == 1 else None
    needed = [GENRES[g] for g in genres if g in GENRES]
    if not needed and not (year_min or year_max):
        return []            # too vague for a shortlist to help
    hits = []
    for kind, title, year, title_genres, rating, votes in titles:
        if want and kind != want:
            continue
        if (year_min and year < year_min) or (year_max and year > year_max):
            continue
        if any(not (set(title_genres) & g) for g in needed):
            continue
        hits.append((rating * math.log10(votes), kind, title, year, rating, votes))
    hits.sort(reverse=True)
    best = hits[:limit - limit // 4]
    this_year = this_year or time.gmtime().tm_year
    recent = [h for h in hits if h[3] >= this_year - 1 and h not in best][:limit // 4]
    return [{'type': kind, 'title': title, 'year': year, 'rating': rating, 'votes': votes}
            for _, kind, title, year, rating, votes in best + recent]


# The big title file (230 MB) is fetched twice a week, ratings (9 MB) daily:
# votes stay current, new titles arrive within 3-4 days (owner, Nov 19).
SCHEDULE_HOURS = {'title.basics.tsv.gz': 3.5 * 24, 'title.ratings.tsv.gz': 20}


def _download(opener, name, folder):
    """Fetch [name] into [folder] unless IMDb has not published a newer copy
    (If-Modified-Since). Returns True when a new file arrived."""
    target = folder / name
    part = folder / f'.{name}.part'
    request = urllib.request.Request(DATASETS + name)
    if target.exists():
        request.add_header('If-Modified-Since',
                           time.strftime('%a, %d %b %Y %H:%M:%S GMT', time.gmtime(target.stat().st_mtime)))
    try:
        with opener.open(request, timeout=300) as response, open(part, 'wb') as f:
            while chunk := response.read(1 << 20):
                f.write(chunk)
    except urllib.error.HTTPError as error:
        part.unlink(missing_ok=True)
        if error.code == 304:
            return False
        raise
    except BaseException:
        part.unlink(missing_ok=True)       # this function's own unfinished download
        raise
    part.replace(target)                   # complete downloads only replace the old one
    return True


def refresh(live_dir, opener=None, now=None):
    """Keep IMDb's files in [live_dir]/imdb on their schedule (kept there, the
    owner keeps downloads inside the smartsearch folder) and rebuild the
    shortlist and the show page's vote counts when either changed. Writes a
    small status file whenever it tried something."""
    live = Path(live_dir)
    folder = live / 'imdb'
    folder.mkdir(exist_ok=True)
    out = live / FILE_NAME
    now = now or time.time()
    due = [name for name, hours in SCHEDULE_HOURS.items()
           if not (folder / name).exists() or now - (folder / name).stat().st_mtime >= hours * 3600]
    if not due and out.exists():
        return 'fresh'
    opener = opener or urllib.request.build_opener(urllib.request.ProxyHandler({}))
    started = time.time()
    try:
        changed = [name for name in due if _download(opener, name, folder)]
        for name in due:                   # checked today, even when IMDb had nothing new
            if name not in changed and (folder / name).exists():
                os.utime(folder / name, (now, now))
        if changed or not out.exists():
            count, ratings = build(folder / 'title.basics.tsv.gz', folder / 'title.ratings.tsv.gz', out)
            _refresh_extras_votes(live, ratings)
            result = {'ok': True, 'built_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                      'titles': count, 'downloaded': changed, 'seconds': round(time.time() - started)}
        else:
            result = {'ok': True, 'checked_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                      'downloaded': [], 'note': 'IMDb had no newer files'}
    except Exception as error:    # never takes the service down; the next check retries
        result = {'ok': False, 'tried_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
                  'error': type(error).__name__}
    status = live / STATUS_NAME
    tmp = status.with_name('.' + status.name + '.tmp')
    tmp.write_text(json.dumps(result), encoding='utf-8')
    tmp.replace(status)
    return 'built' if result['ok'] and result.get('downloaded') else ('failed' if not result['ok'] else 'checked')


def _refresh_extras_votes(live, ratings):
    """Keep the show page's IMDb vote counts current (crew stays as built)."""
    from . import imdb_extras
    path = live / imdb_extras.FILE_NAME
    try:
        doc = json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return
    for imdb, entry in doc.get('titles', {}).items():
        if imdb in ratings:
            entry['r'], entry['v'] = ratings[imdb]
    doc['votes_utc'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    tmp = path.with_name('.' + path.name + '.tmp')
    tmp.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    tmp.replace(path)
