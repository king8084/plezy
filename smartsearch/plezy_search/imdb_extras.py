"""Crew and vote counts from IMDb's public datasets, for library titles only.

Jellyfin's metadata here lists cast but no directors, and has no vote counts.
IMDb publishes both (https://datasets.imdbws.com, personal/non-commercial
use): title.crew (directors, writers), name.basics (their names) and
title.ratings (votes). [build] keeps only the library's IMDb ids and writes a
small JSON file next to the index; the service reads it on refresh. Nothing
in Jellyfin or the index database is changed.

File shape: {"version": 1, "built_utc": ..., "titles": {"tt0111161":
{"d": ["Frank Darabont"], "w": [...], "v": 3012345, "r": 9.3}}}
"""

import csv
import gzip
import json
import sys
import time
from pathlib import Path

FILE_NAME = 'imdb_extras.json'
VERSION = 1
MAX_WRITERS = 4

csv.field_size_limit(10 ** 7)


def _rows(path):
    with gzip.open(path, 'rt', encoding='utf-8', newline='') as f:
        reader = csv.reader(f, delimiter='\t', quoting=csv.QUOTE_NONE)
        next(reader, None)
        yield from reader


def _ids(value):
    return [] if not value or value == '\\N' else value.split(',')


def build(dataset_dir, imdb_ids, out_path):
    """Join the three datasets for [imdb_ids]; write [out_path] atomically."""
    dataset_dir = Path(dataset_dir)
    wanted = {i.strip().lower() for i in imdb_ids if i}
    crew = {}
    people = set()
    for row in _rows(dataset_dir / 'title.crew.tsv.gz'):
        if row[0] in wanted:
            directors, writers = _ids(row[1]), _ids(row[2])[:MAX_WRITERS]
            crew[row[0]] = (directors, writers)
            people.update(directors)
            people.update(writers)
    names = {}
    for row in _rows(dataset_dir / 'name.basics.tsv.gz'):
        if row[0] in people:
            names[row[0]] = row[1]
    ratings = {}
    for row in _rows(dataset_dir / 'title.ratings.tsv.gz'):
        if row[0] in wanted:
            try:
                ratings[row[0]] = (float(row[1]), int(row[2]))
            except ValueError:
                pass
    titles = {}
    for imdb in sorted(wanted):
        entry = {}
        directors, writers = crew.get(imdb, ([], []))
        d = [names[n] for n in directors if n in names]
        w = [names[n] for n in writers if n in names and names[n] not in d]
        if d:
            entry['d'] = d
        if w:
            entry['w'] = w
        if imdb in ratings:
            entry['r'], entry['v'] = ratings[imdb]
        if entry:
            titles[imdb] = entry
    doc = {'version': VERSION, 'built_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
           'source': 'IMDb non-commercial datasets', 'titles': titles}
    out_path = Path(out_path)
    tmp = out_path.with_name(out_path.name + '.tmp')
    tmp.write_text(json.dumps(doc, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
    tmp.replace(out_path)
    return len(titles)


def load(path):
    """{imdb_id: entry}, or {} when the file is missing or unreadable."""
    try:
        doc = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return {}
    if doc.get('version') != VERSION or not isinstance(doc.get('titles'), dict):
        return {}
    return doc['titles']


if __name__ == '__main__':
    # python -m plezy_search.imdb_extras DATASET_DIR IDS_JSON OUT_JSON
    count = build(sys.argv[1], json.loads(Path(sys.argv[2]).read_text()), sys.argv[3])
    print(f'{count} titles')
