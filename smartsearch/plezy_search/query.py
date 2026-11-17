"""Understand a typed search request without any AI call (instant path).

"sci fi shows over 8"        -> kind=Series, genre=Sci-Fi, rating>8
"90s comedies with jim carrey" -> years 1990-1999, genre=Comedy, person=Jim Carrey
"best korean thriller movies"  -> kind=Movie, genre=Thriller, language=ko, sort=rating

Whatever is not understood stays as free text for title/full-text and
semantic matching, so nothing the user typed is thrown away.
"""

import datetime as dt
import re
from dataclasses import dataclass, field

from .common import norm

# Concept -> genre names. Shows and movies use different TMDB vocabularies on
# this server ("Sci-Fi & Fantasy" vs "Science Fiction"), so each kind has its own.
GENRES = {
    'scifi': ({'Science Fiction'}, {'Sci-Fi & Fantasy'}),
    'fantasy': ({'Fantasy'}, {'Sci-Fi & Fantasy'}),
    'action': ({'Action'}, {'Action & Adventure'}),
    'adventure': ({'Adventure'}, {'Action & Adventure'}),
    'comedy': ({'Comedy'}, {'Comedy'}),
    'drama': ({'Drama'}, {'Drama'}),
    'crime': ({'Crime'}, {'Crime'}),
    'mystery': ({'Mystery'}, {'Mystery'}),
    'thriller': ({'Thriller'}, {'Mystery', 'Crime'}),
    'horror': ({'Horror'}, set()),
    'romance': ({'Romance'}, set()),
    'animation': ({'Animation'}, {'Animation'}),
    'documentary': ({'Documentary'}, {'Documentary'}),
    'family': ({'Family'}, {'Family'}),
    'kids': ({'Family', 'Animation'}, {'Kids'}),
    'war': ({'War'}, {'War & Politics'}),
    'politics': (set(), {'War & Politics'}),
    'history': ({'History'}, set()),
    'western': ({'Western'}, {'Western'}),
    'music': ({'Music'}, set()),
    'reality': (set(), {'Reality'}),
    'soap': (set(), {'Soap'}),
    'talk': (set(), {'Talk'}),
    'news': (set(), {'News'}),
    'anime': ({'Animation'}, {'Animation'}),
}
# Genres with no TV equivalent fall back to TMDB keywords (tags) for shows.
TAG_FALLBACK = {'horror': {'horror', 'supernatural', 'zombie', 'vampire', 'ghost'},
                'romance': {'romance', 'romantic comedy', 'love'},
                'thriller': {'thriller', 'psychological thriller'},
                'history': {'historical', 'history', 'period drama'},
                'music': {'music', 'musical'}}

GENRE_WORDS = {
    'scifi': ['sci fi', 'scifi', 'sci-fi', 'science fiction', 'science-fiction'],
    'fantasy': ['fantasy'],
    'action': ['action'],
    'adventure': ['adventure', 'adventures'],
    'comedy': ['comedy', 'comedies', 'funny', 'comedic', 'sitcom', 'sitcoms'],
    'drama': ['drama', 'dramas', 'dramatic'],
    'crime': ['crime', 'gangster', 'gangsters', 'mafia'],
    'mystery': ['mystery', 'mysteries', 'whodunit', 'detective'],
    'thriller': ['thriller', 'thrillers', 'suspense'],
    'horror': ['horror', 'scary', 'creepy', 'spooky'],
    'romance': ['romance', 'romantic', 'rom com', 'romcom', 'rom-com', 'love story'],
    'animation': ['animated', 'animation', 'cartoon', 'cartoons'],
    'documentary': ['documentary', 'documentaries', 'docuseries', 'docs', 'doc'],
    'family': ['family'],
    'kids': ['kids', 'children', 'childrens', "children's", 'kid'],
    'war': ['war'],
    'politics': ['political', 'politics'],
    'history': ['historical', 'history', 'period'],
    'western': ['western', 'westerns', 'cowboy'],
    'music': ['musical', 'musicals', 'music'],
    'reality': ['reality'],
    'soap': ['soap', 'soaps', 'soap opera'],
    'talk': ['talk show', 'talk shows'],
    'news': ['news'],
    'anime': ['anime', 'animes'],
}

KIND_WORDS = {
    'Series': ['tv shows', 'tv show', 'tv series', 'shows', 'show', 'series', 'tv', 'sitcom', 'sitcoms', 'miniseries'],
    'Movie': ['movies', 'movie', 'films', 'film', 'flicks', 'flick', 'cinema'],
    'Episode': ['episodes', 'episode', 'ep'],
}

LANGUAGES = {
    'korean': 'ko', 'k drama': 'ko', 'kdrama': 'ko', 'k-drama': 'ko', 'japanese': 'ja',
    'chinese': 'zh', 'mandarin': 'zh', 'cantonese': 'cn', 'spanish': 'es', 'french': 'fr', 'german': 'de',
    'italian': 'it', 'hindi': 'hi', 'bollywood': 'hi', 'turkish': 'tr', 'arabic': 'ar', 'danish': 'da',
    'swedish': 'sv', 'norwegian': 'no', 'russian': 'ru', 'portuguese': 'pt', 'thai': 'th', 'polish': 'pl',
    'dutch': 'nl', 'english': 'en',
}

STUDIOS = {
    'netflix': ['netflix'], 'hbo': ['hbo', 'hbo max', 'max'], 'apple tv': ['apple tv', 'apple tv+'],
    'appletv': ['apple tv', 'apple tv+'], 'disney': ['disney+', 'disney', 'disney channel'],
    'amazon': ['prime video', 'amazon'], 'prime video': ['prime video', 'amazon'], 'hulu': ['hulu'],
    'bbc': ['bbc one', 'bbc two', 'bbc three', 'bbc', 'bbc iplayer'], 'paramount': ['paramount+', 'paramount'],
    'peacock': ['peacock'], 'showtime': ['showtime'], 'starz': ['starz'], 'fx': ['fx', 'fxx', 'fx on hulu'],
    'amc': ['amc', 'amc+'], 'nbc': ['nbc'], 'abc': ['abc', 'abc (us)'], 'cbs': ['cbs'], 'fox': ['fox'],
    'pixar': ['pixar'], 'marvel': ['marvel studios', 'marvel'], 'a24': ['a24'], 'ghibli': ['studio ghibli'],
    'cartoon network': ['cartoon network'], 'adult swim': ['adult swim'], 'crunchyroll': ['crunchyroll'],
}

SORT_WORDS = {
    'rating': ['best', 'top rated', 'top-rated', 'highest rated', 'highly rated', 'top', 'greatest', 'acclaimed', 'must watch', 'must-watch'],
    'newest': ['newest', 'latest', 'recent', 'new', 'newer'],
    'oldest': ['oldest', 'classic', 'classics', 'old'],
}

FILLER = {'find', 'me', 'show me', 'give', 'give me', 'i', 'want', 'to', 'watch', 'some', 'any', 'a', 'an',
          'the', 'with', 'that', 'are', 'is', 'which', 'and', 'of', 'please', 'pls', 'search', 'for', 'list',
          'looking', 'something', 'like', 'good', 'great', 'rated', 'rating', 'ratings', 'imdb', 'score',
          'stars', 'star', 'from', 'in', 'on', 'by', 'all', 'what', 'whats', "what's", 'can', 'you', 'recommend',
          'suggest', 'should', 'have', 'has', 'got', 'than', 'about', 'starring', 'featuring', 'directed'}

NUMBER = r'(\d{1,2}(?:[.,]\d)?)(?![\d.,]*\d)'
UNITS = r'(?!\s*(?:min|mins|minutes|hours?|hrs?|seasons?|episodes?|eps?|years?|s\b|%))'


@dataclass
class Parsed:
    text: str                      # leftover free text (for full-text + semantic)
    original: str
    kinds: set = field(default_factory=set)
    genres: list = field(default_factory=list)       # concept names; all must match
    rating_min: float = None
    rating_max: float = None
    year_min: int = None
    year_max: int = None
    runtime_max: int = None
    runtime_min: int = None
    languages: set = field(default_factory=set)
    studios: list = field(default_factory=list)      # each entry: list of acceptable studio norms
    status: str = None
    people: list = field(default_factory=list)       # normalised names; all must match
    sort: str = None
    unwatched: bool = False        # applied by the app with the viewer's own watch state
    soft_genres: list = field(default_factory=list)  # genre words inside a description: ranking hints only
    understood: list = field(default_factory=list)   # human-readable chips for the UI

    @property
    def has_filters(self):
        return bool(self.kinds or self.genres or self.rating_min is not None or self.rating_max is not None
                    or self.year_min or self.year_max or self.runtime_max or self.runtime_min or self.languages
                    or self.studios or self.status or self.people)

    def as_dict(self):
        return {k: (sorted(v) if isinstance(v, set) else v) for k, v in self.__dict__.items()}


def _phrases(table):
    out = []
    for key, words in table.items():
        for w in words:
            out.append((norm(w), key))
    return sorted(out, key=lambda x: -len(x[0]))


_GENRE_PHRASES = _phrases(GENRE_WORDS)
_KIND_PHRASES = _phrases(KIND_WORDS)
_SORT_PHRASES = _phrases(SORT_WORDS)
_LANG_PHRASES = sorted(((norm(k), v) for k, v in LANGUAGES.items()), key=lambda x: -len(x[0]))
_STUDIO_PHRASES = sorted(((norm(k), [norm(x) for x in v]) for k, v in STUDIOS.items()), key=lambda x: -len(x[0]))


def _take(text, phrase):
    """Remove a whole-word phrase from text; return (found, remaining)."""
    pattern = r'(?<!\w)' + re.escape(phrase) + r'(?!\w)'
    if re.search(pattern, text):
        return True, re.sub(pattern, ' ', text, count=1)
    return False, text


_UNWATCHED = re.compile(
    r"(?<!\w)(?:un-?watched|unseen|not (?:yet )?(?:watched|seen)|(?:i )?(?:have ?n'?t|have not|did ?n'?t|never) "
    r"(?:watched|seen)(?: yet)?|new to me|i have not seen|(?:that )?i ?(?:'ve|have) not (?:watched|seen))(?!\w)")


def _unwatched(text, p):
    m = _UNWATCHED.search(text)
    if not m:
        return text
    p.unwatched = True
    p.understood.append('Unwatched')
    return text[:m.start()] + ' ' + text[m.end():]


def _rating(text, p):
    def num(s):
        return float(s.replace(',', '.'))
    patterns = [
        (r'(?:rated|rating|imdb|score)?\s*(?:over|above|more than|greater than|higher than|better than|>)\s*' + NUMBER + UNITS, 'min_excl'),
        (r'(?:rated|rating|imdb|score)?\s*(?:at least|min(?:imum)?|>=)\s*' + NUMBER + UNITS, 'min'),
        (NUMBER + r'\s*(?:\+|plus|or (?:more|higher|above|better))\s*(?:rated|rating|imdb|stars?)?', 'min'),
        (r'(?:rated|rating|imdb|score)\s*(?:of\s*)?' + NUMBER + UNITS, 'min'),
        (r'(?:rated|rating|imdb|score)?\s*(?:under|below|less than|lower than|<)\s*' + NUMBER + UNITS, 'max'),
    ]
    for pat, mode in patterns:
        m = re.search(r'(?<!\w)' + pat, text)
        if not m:
            continue
        value = num(m.group(1))
        if not 0 < value <= 10:
            continue
        if mode == 'max':
            # "under 8" only means rating when the request mentions rating words
            if not re.search(r'rat|imdb|score|star', p.original.casefold()):
                continue
            p.rating_max = value
            p.understood.append(f'IMDb under {value:g}')
        else:
            p.rating_min = value + (0.001 if mode == 'min_excl' else 0)
            p.understood.append(f'IMDb {"over" if mode == "min_excl" else "at least"} {value:g}')
        return text[:m.start()] + ' ' + text[m.end():]
    return text


def _years(text, p, today):
    m = re.search(r'(?<!\w)(?:(?:from|in) (?:the )?)?(?:(19|20)?(\d)0)\s*\'?s(?!\w)', text)  # 90s, 1990s, 2010s
    if m:
        century = m.group(1)
        decade = int(m.group(2))
        start = int((century or ('19' if decade >= 3 else '20')) + str(decade) + '0')
        p.year_min, p.year_max = start, start + 9
        p.understood.append(f'{start}s')
        return text[:m.start()] + ' ' + text[m.end():]
    m = re.search(r'(?<!\w)between (\d{4}) and (\d{4})(?!\w)', text)
    if m:
        a, b = sorted((int(m.group(1)), int(m.group(2))))
        p.year_min, p.year_max = a, b
        p.understood.append(f'{a}–{b}')
        return text[:m.start()] + ' ' + text[m.end():]
    m = re.search(r'(?<!\w)(after|since|before|from|in|older than|newer than)?\s*((?:19|20)\d\d)(?!\w)', text)
    if m and 1900 <= int(m.group(2)) <= today.year + 2:
        year, word = int(m.group(2)), (m.group(1) or 'in')
        if word in ('after', 'since', 'newer than'):
            p.year_min = year + (1 if word == 'after' else 0)
            p.understood.append(f'{"after" if word == "after" else "since"} {year}')
        elif word in ('before', 'older than'):
            p.year_max = year - 1
            p.understood.append(f'before {year}')
        else:
            p.year_min = p.year_max = year
            p.understood.append(str(year))
        return text[:m.start()] + ' ' + text[m.end():]
    m = re.search(r'(?<!\w)(?:last|past) (\d{1,2}) years?(?!\w)', text)
    if m:
        p.year_min = today.year - int(m.group(1))
        p.understood.append(f'last {m.group(1)} years')
        return text[:m.start()] + ' ' + text[m.end():]
    return text


def _runtime(text, p):
    m = re.search(r'(?<!\w)(under|less than|shorter than|below|over|more than|longer than)\s*(\d{1,3})\s*(min|mins|minutes|hours?|hrs?|h)(?!\w)', text)
    if m:
        minutes = int(m.group(2)) * (60 if m.group(3).startswith('h') else 1)
        if m.group(1) in ('under', 'less than', 'shorter than', 'below'):
            p.runtime_max = minutes
            p.understood.append(f'under {minutes} min')
        else:
            p.runtime_min = minutes
            p.understood.append(f'over {minutes} min')
        return text[:m.start()] + ' ' + text[m.end():]
    return text


def parse(query, vocab=None, today=None):
    """vocab (optional): {'people': {norm_name: display}, 'studios': {norm}, ...}."""
    today = today or dt.date.today()
    p = Parsed(text='', original=query)
    text = ' ' + str(query or '').casefold().replace('’', "'") + ' '
    text = _unwatched(text, p)
    text = _runtime(text, p)
    text = _rating(text, p)
    text = _years(text, p, today)
    text = ' ' + norm(text) + ' '

    for phrase, kind in _KIND_PHRASES:
        found, text = _take(text, phrase)
        if found:
            p.kinds.add(kind)
            if phrase in ('sitcom', 'sitcoms') and 'comedy' not in p.genres:
                p.genres.append('comedy')
    for phrase, concept in _GENRE_PHRASES:
        found, text = _take(text, phrase)
        if found and concept not in p.genres:
            p.genres.append(concept)
    for phrase, code in _LANG_PHRASES:
        found, text = _take(text, phrase)
        if found:
            p.languages.add(code)
            p.understood.append(phrase.title())
    for phrase, studios in _STUDIO_PHRASES:
        found, text = _take(text, phrase)
        if found:
            p.studios.append(studios)
            p.understood.append(phrase.upper() if len(phrase) <= 3 else phrase.title())
    for phrase in ('ended', 'finished', 'completed', 'cancelled', 'canceled'):
        found, text = _take(text, phrase)
        if found:
            p.status = 'Ended'
            p.understood.append('Ended')
            break
    for phrase in ('ongoing', 'still running', 'continuing', 'still airing', 'airing'):
        found, text = _take(text, phrase)
        if found:
            p.status = 'Continuing'
            p.understood.append('Still running')
            break
    for phrase, sort in _SORT_PHRASES:
        found, text = _take(text, phrase)
        if found and not p.sort:
            p.sort = sort
    if vocab and vocab.get('people'):
        text = _people(text, p, vocab['people'])

    for concept in p.genres:
        p.understood.insert(0, concept.replace('scifi', 'Sci-Fi').title() if concept != 'scifi' else 'Sci-Fi')
    for kind in sorted(p.kinds):
        p.understood.insert(0, {'Series': 'Shows', 'Movie': 'Movies', 'Episode': 'Episodes'}[kind])

    words = [w for w in text.split() if w not in FILLER]
    p.text = ' '.join(words)
    # A sentence describing a plot ("a cop teams up with a detective to ...") often
    # contains genre words by accident. Only list-style requests make them filters.
    explicit = (p.kinds or p.rating_min is not None or p.rating_max is not None or p.year_min or p.year_max
                or p.people or p.studios or p.status or p.runtime_max or p.runtime_min or p.unwatched)
    if len(words) >= 3:
        # Describing a plot: genre words are hints ("a poor family" is not the Family genre).
        if p.genres:
            p.soft_genres, p.genres = p.genres, []
            p.understood = [u for u in p.understood if u not in _genre_labels(p.soft_genres)]
        # Nationality words only filter in list-style requests ("korean movies about ..." keeps them).
        if p.languages and not explicit:
            soft_langs = {k.title() for k, v in LANGUAGES.items() if v in p.languages}
            p.languages = set()
            p.understood = [u for u in p.understood if u not in soft_langs]
    return p


def _genre_labels(concepts):
    return {('Sci-Fi' if c == 'scifi' else c.title()) for c in concepts}


def _people(text, p, people):
    """Greedy longest match of 2-3 word names against the library's cast/crew."""
    words = text.split()
    i, kept = 0, []
    while i < len(words):
        for size in (3, 2):
            chunk = ' '.join(words[i:i + size])
            if len(words[i:i + size]) == size and chunk in people:
                p.people.append(chunk)
                p.understood.append(people[chunk])
                i += size
                break
        else:
            kept.append(words[i])
            i += 1
    return ' ' + ' '.join(kept) + ' '


def genre_names(concept, kind):
    movie, series = GENRES.get(concept, (set(), set()))
    return movie if kind == 'Movie' else series


def tag_fallback(concept):
    return TAG_FALLBACK.get(concept, set())
