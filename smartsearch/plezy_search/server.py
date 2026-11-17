"""HTTP API for the Plezy app (LAN only, key required).

GET /v1/search?q=...           instant results (no AI; works with the PC asleep)
GET /v1/smart?q=...&verify=0   meaning-based results (needs Ollama for new queries)
GET /v1/verify?q=...&ids=a,b   confirmed / possible labels for smart results
GET /v1/health                 counts and AI availability
GET /v1/status                 indexer progress
"""

import argparse
import hashlib
import hmac
import json
import re
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .clients import Ollama
from .common import SearchError, api, endpoint
from .query import parse as _parse
from .search import Engine


def engine_parse(q, engine):
    return _parse(q, engine.vocab)

MAX_QUERY = 200


class Handler(BaseHTTPRequestHandler):
    server_version = 'PlezySmartSearch/1'
    sys_version = ''

    def log_message(self, fmt, *args):   # never log query text
        pass

    def _send(self, code, body):
        data = json.dumps(body, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def _authorised(self):
        """Service key, or the caller's own Jellyfin token (verified with Jellyfin)."""
        key = self.server.api_key
        given = self.headers.get('X-Plezy-Key') or ''
        auth = self.headers.get('Authorization') or ''
        if auth.startswith('Bearer '):
            given = auth[7:]
        if given and key and hmac.compare_digest(given.encode(), key.encode()):
            return True
        token = self.headers.get('X-Emby-Token') or ''
        if not token:
            m = re.search(r'Token="([^"]+)"', auth)
            token = m.group(1) if m else ''
        return bool(token) and self.server.jellyfin_user(token) is not None

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        args = {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}
        if url.path == '/v1/ping':
            # Public: lets the app check this index belongs to the server it is connected to.
            return self._send(200, {'ok': True, 'server_id': self.server.server_id, 'api': 1})
        if not self._authorised():
            return self._send(401, {'error': 'unauthorised'})
        engine = self.server.engine
        try:
            q = (args.get('q') or '').strip()[:MAX_QUERY]
            limit = max(1, min(int(args.get('limit', 40)), 100))
            if url.path == '/v1/search':
                return self._send(200, engine.instant(q, limit) if q else {'query': '', 'results': []})
            if url.path == '/v1/smart':
                if not q:
                    return self._send(200, {'query': '', 'results': []})
                # Fast re-rank with the local checker by default; confirm=1 adds the
                # slower second vote (the app asks /v1/verify for that separately).
                # recall=1 adds the generator's knowledge of famous titles (~1 s warm).
                return self._send(200, engine.smart(q, min(limit, 30), verify=args.get('rerank', '1') == '1',
                                                    confirm=args.get('confirm', '0') == '1',
                                                    recall=args.get('recall', '1') == '1',
                                                    series=args.get('series') or None))
            if url.path == '/v1/verify':
                ids = [x for x in (args.get('ids') or '').split(',') if x][:8]
                if not engine.verifier:
                    return self._send(503, {'error': 'verification unavailable'})
                scoped = engine._series_in(engine_parse(q, engine))
                return self._send(200, {'query': q, 'verdicts': engine.verifier.check(
                    q, ids, shows=[scoped[0]] if scoped else [])})
            if url.path == '/v1/top':
                kinds = tuple(k for k in (args.get('kinds') or 'Movie,Series').split(',') if k in ('Movie', 'Series'))
                return self._send(200, engine.top_rated(kinds or ('Movie', 'Series'),
                                                        float(args.get('min_rating', 7.5)), min(limit, 100)))
            if url.path == '/v1/resolve':
                refs = [x for x in (args.get('refs') or '').split(',') if x][:200]
                return self._send(200, engine.resolve(refs, args.get('seed') or None, min(limit, 100)))
            if url.path == '/v1/similar':
                return self._send(200, engine.similar(args.get('id', ''), min(limit, 100)))
            if url.path == '/v1/health':
                return self._send(200, self.server.health())
            if url.path == '/v1/status':
                status = self.server.data / 'status.json'
                return self._send(200, json.loads(status.read_text()) if status.exists() else {})
            return self._send(404, {'error': 'not found'})
        except SearchError as error:
            return self._send(503, {'error': str(error)})
        except (ValueError, KeyError):
            return self._send(400, {'error': 'bad request'})


class Server(ThreadingHTTPServer):
    daemon_threads = True

    TOKEN_TTL = 600

    def __init__(self, address, engine, api_key, data, jellyfin_url=None):
        super().__init__(address, Handler)
        self.engine = engine
        self.api_key = api_key
        self.data = data
        self.jellyfin = endpoint(jellyfin_url, jellyfin=True) if jellyfin_url else None
        self.server_id = (store_get(engine, 'source') or {}).get('server_id')
        self._tokens = {}
        self._token_lock = threading.Lock()

    def jellyfin_user(self, token):
        """Validate a Jellyfin access token by asking Jellyfin who it belongs to.

        Only a hash of the token is kept (in memory, 10 minutes). Tokens are never logged.
        """
        if not self.jellyfin or len(token) > 256 or not re.fullmatch(r'[A-Za-z0-9-]+', token):
            return None
        digest = hashlib.sha256(token.encode()).hexdigest()
        now = time.monotonic()
        with self._token_lock:
            hit = self._tokens.get(digest)
            if hit and hit[1] > now:
                return hit[0]
        try:
            # Token only: no client/device fields, so the app's own device entry
            # in Jellyfin is never renamed by this check.
            data, _ = api(self.jellyfin, '/Users/Me', {'Authorization': 'MediaBrowser Token="' + token + '"'}, timeout=5)
            user = data.get('Id') if isinstance(data, dict) else None
        except SearchError:
            user = None
        with self._token_lock:
            if len(self._tokens) > 500:
                self._tokens.clear()
            if user:
                self._tokens[digest] = (user, now + self.TOKEN_TTL)
        return user

    def health(self):
        db = self.engine.db
        total, embedded = db.execute('SELECT count(*), count(embedding_key) FROM items WHERE active=1').fetchone()
        ai = False
        if self.engine.ollama:
            try:
                ai = self.engine.ollama.available()
            except SearchError:
                ai = False
        return {'ok': True, 'items': total, 'embedded': embedded, 'ai_available': ai,
                'verifier': bool(self.engine.verifier), 'vectors_loaded': len(self.engine.vectors[1]) if self.engine.vectors else 0}


def store_get(engine, key):
    from . import store
    return store.get(engine.db, key)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument('data_dir', type=Path)
    parser.add_argument('--config', type=Path, required=True, help='service.json')
    args = parser.parse_args(argv)
    config = json.loads(args.config.read_text())
    access = json.loads(Path(config['access_file']).read_text())
    model = config['model']
    db_path = args.data_dir / 'index.sqlite'
    while not db_path.exists():
        time.sleep(5)
    engine = Engine(db_path, Ollama(access, model), model)
    if config.get('nli_provenance'):
        try:
            from .verify import Verifier
            engine.verifier = Verifier(engine, access, config['nli_provenance'], args.data_dir / 'verify-cache.sqlite')
        except Exception as error:   # explicit: labels unavailable, never a silent old-checker fallback
            print(json.dumps({'verifier': 'unavailable', 'reason': type(error).__name__}), flush=True)

    def refresher():
        while True:
            time.sleep(30)
            try:
                engine.refresh()
            except Exception as error:
                print(json.dumps({'refresh_error': type(error).__name__}), flush=True)
    threading.Thread(target=refresher, daemon=True).start()
    server = Server(('0.0.0.0', int(config.get('port', 8787))), engine, config['api_key'], args.data_dir,
                    jellyfin_url=access.get('jellyfin_url'))
    print(json.dumps({'listening': config.get('port', 8787)}), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
