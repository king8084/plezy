"""Shared helpers for the Plezy smart-search service.

Safety model: the service only *reads* Jellyfin through its HTTP API with a
restricted (non-admin, deletion-disabled) account, and only *writes* inside
its own data directory. Nothing here touches media or Jellyfin-managed files.
"""

import array
import datetime as dt
import hashlib
import html
import json
import math
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

# Embedding identity. These must stay byte-compatible with the pilot
# (scripts/search_index_pilot.py) so the carried-over seed vectors stay valid.
FORMAT = 'plezy-metadata-v1'
DIMENSIONS = 768
MAX_RESPONSE = 16 * 1024 * 1024
NETWORK_FS = {'nfs', 'nfs4', 'cifs', 'smb3', 'smbfs', 'fuse.sshfs', 'autofs', '9p'}


class SearchError(Exception):
    """Expected operational failure. Messages never contain secrets."""


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha(value):
    return hashlib.sha256(value if isinstance(value, bytes) else value.encode()).hexdigest()


def packed(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))


def save_json(path, value):
    """Write a small JSON file in place (truncate + write).

    Deliberately no temp-file-and-rename: on Unraid nothing may ever be
    deleted, and a rename-over unlinks the previous file.
    """
    data = (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data)
        stream.flush()
        os.fsync(stream.fileno())


class _TextOnly(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)


def plain(value):
    """Same normalisation as the pilot: strip markup, unescape, collapse space."""
    parser = _TextOnly()
    parser.feed(str(value or ''))
    return ' '.join(html.unescape(' '.join(parser.parts)).split())


def norm(value):
    """Case/diacritic-insensitive key for terms such as genres and names."""
    import unicodedata
    text = unicodedata.normalize('NFKD', str(value or '')).casefold()
    text = ''.join(c for c in text if not unicodedata.combining(c))
    return ' '.join(re.sub(r'[^\w]+', ' ', text).split())


def endpoint(value, jellyfin=False):
    p = urllib.parse.urlsplit(str(value).strip())
    if p.scheme not in ('http', 'https') or not p.hostname or p.username or p.password or p.query:
        raise SearchError('Invalid endpoint configuration')
    path = p.path.rstrip('/')
    if jellyfin:
        path = path.split('/web', 1)[0]
    return urllib.parse.urlunsplit((p.scheme, p.netloc, path, '', ''))


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}), _NoRedirect())


def api(base, path, headers=None, body=None, timeout=30, method=None):
    """JSON request. Errors are reported without URLs, bodies or credentials."""
    data = None if body is None else json.dumps(body).encode()
    h = {'Accept': 'application/json', **(headers or {})}
    if data is not None:
        h['Content-Type'] = 'application/json'
    req = urllib.request.Request(base + path, data=data, headers=h, method=method)
    start = time.perf_counter()
    try:
        with _OPENER.open(req, timeout=timeout) as response:
            raw = response.read(MAX_RESPONSE + 1)
    except urllib.error.HTTPError as error:
        raise SearchError('HTTP status ' + str(error.code)) from None
    except (urllib.error.URLError, OSError):
        raise SearchError('connection failed') from None
    if len(raw) > MAX_RESPONSE:
        raise SearchError('response exceeded size limit')
    try:
        result = json.loads(raw) if raw else {}
    except ValueError:
        raise SearchError('invalid JSON response') from None
    if isinstance(result, dict) and result.get('error'):
        raise SearchError('service reported an error')
    return result, round((time.perf_counter() - start) * 1000, 3)


def vector_blob(values):
    """Normalised little-endian float32, identical to the pilot's encoding."""
    if len(values) != DIMENSIONS or not all(isinstance(x, (float, int)) and math.isfinite(x) for x in values):
        raise SearchError('invalid embedding')
    n = math.sqrt(sum(x * x for x in values))
    if n == 0:
        raise SearchError('zero embedding')
    v = array.array('f', (x / n for x in values))
    if sys.byteorder != 'little':
        v.byteswap()
    return v.tobytes()


def embedding_key(model_digest, document):
    """Content-addressed key; same formula as the pilot so vectors carry over."""
    return sha(model_digest + ':' + FORMAT + ':' + sha(document))


def filesystem_type(path):
    path = Path(path).resolve()
    best = (-1, None)
    for line in Path('/proc/self/mountinfo').read_text().splitlines():
        left, right = line.split(' - ', 1)
        mount = Path(left.split()[4].replace('\\040', ' '))
        if path == mount or mount in path.parents:
            best = max(best, (len(str(mount)), right.split()[0]))
    if best[1] is None:
        raise SearchError('could not determine filesystem')
    return best[1]


def require_local_disk(path):
    """A live SQLite writer must never sit on a network share."""
    kind = filesystem_type(path)
    if kind in NETWORK_FS or kind.startswith('fuse'):
        raise SearchError('refusing to write a live database on a network filesystem')
    return kind
