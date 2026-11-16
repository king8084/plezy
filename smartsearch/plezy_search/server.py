"""HTTP API for the Plezy app (LAN only, key required).

GET /v1/search?q=...           instant results (no AI; works with the PC asleep)
GET /v1/smart?q=...&verify=0   meaning-based results (needs Ollama for new queries)
GET /v1/verify?q=...&ids=a,b   confirmed / possible labels for smart results
GET /v1/health                 counts and AI availability
GET /v1/status                 indexer progress
"""

import argparse
import hmac
import json
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from .clients import Ollama
from .common import SearchError
from .search import Engine

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
        key = self.server.api_key
        given = self.headers.get('X-Plezy-Key') or ''
        auth = self.headers.get('Authorization') or ''
        if auth.startswith('Bearer '):
            given = auth[7:]
        return bool(key) and hmac.compare_digest(given.encode(), key.encode())

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        args = {k: v[-1] for k, v in urllib.parse.parse_qs(url.query).items()}
        if url.path == '/v1/ping':
            return self._send(200, {'ok': True})
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
                return self._send(200, engine.smart(q, min(limit, 30), verify=args.get('rerank', '1') == '1',
                                                    confirm=args.get('confirm', '0') == '1'))
            if url.path == '/v1/verify':
                ids = [x for x in (args.get('ids') or '').split(',') if x][:8]
                if not engine.verifier:
                    return self._send(503, {'error': 'verification unavailable'})
                return self._send(200, {'query': q, 'verdicts': engine.verifier.check(q, ids)})
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

    def __init__(self, address, engine, api_key, data):
        super().__init__(address, Handler)
        self.engine = engine
        self.api_key = api_key
        self.data = data

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
    server = Server(('0.0.0.0', int(config.get('port', 8787))), engine, config['api_key'], args.data_dir)
    print(json.dumps({'listening': config.get('port', 8787)}), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
