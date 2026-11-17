"""Turn Jellyfin item JSON into index records.

The embedding document format is frozen to the pilot's so carried-over vectors
remain valid. Everything else (genres, IMDb rating, cast, tags, networks...) is
stored as structured, filterable fields alongside it.
"""

from .common import norm, packed, plain, sha

KINDS = ('Series', 'Movie', 'Episode')  # Series first so episodes can inherit them

# CommunityRating, CriticRating, ProductionYear, RunTimeTicks, Status and
# OriginalLanguage are returned by default; the rest must be requested.
BASE_FIELDS = ('Overview,ProviderIds,DateCreated,DateLastSaved,Genres,Tags,Studios,'
               'OfficialRating,PremiereDate,ParentId,OriginalTitle')
PEOPLE_FIELDS = BASE_FIELDS + ',People'

MAX_ACTORS = 25
CREW_TYPES = {'Director', 'Writer', 'Creator', 'Producer'}
MAX_CREW = 8


def fields_for(kind):
    # Episode guest-star lists are large and rarely what people search for.
    return BASE_FIELDS if kind == 'Episode' else PEOPLE_FIELDS


def _int(value):
    return value if isinstance(value, int) and not isinstance(value, bool) else None


def _num(value):
    return float(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else None


def _names(values):
    out = []
    for v in values or []:
        name = plain(v.get('Name') if isinstance(v, dict) else v)
        if name and name not in out:
            out.append(name)
    return out


def _people(raw):
    actors, crew = [], []
    for p in raw.get('People') or []:
        if not isinstance(p, dict):
            continue
        name = plain(p.get('Name'))
        if not name:
            continue
        entry = {'name': name, 'type': p.get('Type') or ''}
        role = plain(p.get('Role'))
        if role:
            entry['role'] = role
        if entry['type'] in ('Actor', 'GuestStar'):
            if len(actors) < MAX_ACTORS:
                actors.append(entry)
        elif entry['type'] in CREW_TYPES and len(crew) < MAX_CREW:
            crew.append(entry)
    return actors + crew


def document_for(kind, title, series, season, episode, overview):
    """Embedding text. Must match the pilot byte for byte (see test)."""
    if kind == 'Episode':
        if series and isinstance(season, int) and isinstance(episode, int):
            heading = series + ' | S' + str(season) + 'E' + str(episode) + ' | ' + title
        else:
            heading = (series + ' | ' if series else '') + title
    else:
        heading = title
    return 'title: ' + heading + ' | text: ' + overview


def build(raw, series_lookup=None):
    """Return a record dict, or None for items the index does not cover."""
    kind = raw.get('Type')
    if kind not in KINDS or not raw.get('Id') or raw.get('LocationType') == 'Virtual':
        return None
    title = plain(raw.get('Name'))
    if not title:
        return None
    series_id = raw.get('SeriesId') if kind == 'Episode' else None
    series = plain(raw.get('SeriesName')) if kind == 'Episode' else ''
    if kind == 'Episode' and not series and series_lookup and series_id:
        series = series_lookup.get(series_id, '')
    season = _int(raw.get('ParentIndexNumber')) if kind == 'Episode' else None
    episode = _int(raw.get('IndexNumber')) if kind == 'Episode' else None
    overview = plain(raw.get('Overview'))
    document = document_for(kind, title, series, season, episode, overview)
    ticks = _num(raw.get('RunTimeTicks'))
    premiere = raw.get('PremiereDate')
    rec = {
        'item_id': raw['Id'],
        'kind': kind,
        'title': title,
        'original_title': plain(raw.get('OriginalTitle')) or None,
        'series_id': series_id,
        'series': series,
        'season': season,
        'episode': episode,
        'episode_end': _int(raw.get('IndexNumberEnd')),
        'overview': overview,
        'year': _int(raw.get('ProductionYear')),
        'premiere': premiere[:10] if isinstance(premiere, str) else None,
        'rating': _num(raw.get('CommunityRating')),   # IMDb rating on this server
        'critic': _num(raw.get('CriticRating')),      # Rotten Tomatoes %
        'official_rating': plain(raw.get('OfficialRating')) or None,
        'runtime_min': round(ticks / 600_000_000) if ticks else None,
        'language': plain(raw.get('OriginalLanguage')) or None,
        'status': plain(raw.get('Status')) or None,
        'genres': _names(raw.get('Genres')),
        'tags': _names(raw.get('Tags')),
        'studios': _names(raw.get('Studios')),
        'people': _people(raw),
        'provider_ids': {k: str(v) for k, v in (raw.get('ProviderIds') or {}).items() if v},
        'parent_id': raw.get('ParentId'),
        'date_created': raw.get('DateCreated'),
        'date_last_saved': raw.get('DateLastSaved'),
        'document': document,
        'content_sha256': sha(document),
    }
    rec['data_sha256'] = sha(packed(rec))
    return rec


def terms(rec):
    """(field, display value, normalised value) rows for filter lookups."""
    rows = []
    for field, values in (('genre', rec['genres']), ('tag', rec['tags']), ('studio', rec['studios'])):
        for v in values:
            rows.append((field, v, norm(v)))
    for p in rec['people']:
        rows.append(('person', p['name'], norm(p['name'])))
        if p.get('role') and p['type'] in ('Actor', 'GuestStar'):
            rows.append(('character', p['role'], norm(p['role'])))
    seen, out = set(), []
    for r in rows:
        if r[2] and (r[0], r[2]) not in seen:
            seen.add((r[0], r[2]))
            out.append(r)
    return out


def text_fields(rec):
    """Columns for the full-text index."""
    people = ' '.join(p['name'] + (' ' + p['role'] if p.get('role') else '') for p in rec['people'])
    labels = ' '.join(rec['genres'] + rec['tags'] + rec['studios'])
    title = rec['title'] + (' ' + rec['original_title'] if rec['original_title'] and rec['original_title'] != rec['title'] else '')
    return title, rec['series'], people, labels, rec['overview']
