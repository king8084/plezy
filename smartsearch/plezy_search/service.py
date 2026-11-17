"""Container entry point: keeps the indexer and API server running.

- Restarts a crashed process with back-off.
- Reloads both when the read-only code folder changes, so updates never need
  the container to be removed or recreated (owner rule: never delete on Unraid).
- Writes only inside the data directory.

Usage: python3 -m plezy_search.service --code /code --config /config/service.json --data /data
"""

import argparse
import hashlib
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path


def code_hash(code):
    h = hashlib.sha256()
    for path in sorted(Path(code).rglob('*.py')):
        if '__pycache__' in path.parts:
            continue
        h.update(str(path.relative_to(code)).encode())
        h.update(path.read_bytes())
    return h.hexdigest()


class Child:
    def __init__(self, name, argv, env, log):
        self.name, self.argv, self.env, self.log = name, argv, env, log
        self.proc = None
        self.failures = 0
        self.next_start = 0

    def ensure(self):
        if self.proc and self.proc.poll() is None:
            return
        if self.proc is not None:
            self.failures += 1
            self.next_start = time.monotonic() + min(300, 5 * 2 ** min(self.failures, 6))
            self.proc = None
        if time.monotonic() >= self.next_start:
            stream = open(self.log, 'ab', buffering=0)
            self.proc = subprocess.Popen(self.argv, env=self.env, stdout=stream, stderr=stream)
            stream.close()

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.send_signal(signal.SIGTERM)
            try:
                self.proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        self.proc = None
        self.failures = 0
        self.next_start = 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--code', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--data', required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    env = dict(os.environ, PYTHONPATH=str(args.code), PYTHONDONTWRITEBYTECODE='1', PYTHONUNBUFFERED='1')
    py = sys.executable
    children = [
        Child('indexer', [py, '-m', 'plezy_search.indexer', str(args.data), '--settings',
                                 str(args.config.parent / 'settings.json')], env, args.data / 'indexer.log'),
        Child('server', [py, '-m', 'plezy_search.server', str(args.data), '--config', str(args.config)], env,
              args.data / 'server.log'),
    ]
    stopping = False

    def stop(*_):
        nonlocal stopping
        stopping = True
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    current = code_hash(args.code)
    last_check = time.monotonic()
    print(json.dumps({'service': 'started', 'code': current[:12]}), flush=True)
    while not stopping:
        for child in children:
            child.ensure()
        if time.monotonic() - last_check > 20:
            last_check = time.monotonic()
            try:
                fresh = code_hash(args.code)
            except OSError:
                fresh = current
            if fresh != current:
                print(json.dumps({'service': 'code changed, reloading', 'code': fresh[:12]}), flush=True)
                for child in children:
                    child.stop()
                current = fresh
        time.sleep(1)
    for child in children:
        child.stop()


if __name__ == '__main__':
    main()
