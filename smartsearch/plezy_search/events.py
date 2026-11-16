"""Jellyfin live library events (LibraryChanged) -> pending_changes queue.

Runs in a background thread. Events only *queue* item IDs; the indexer then
re-reads those items through the API. Reconnects trigger a catch-up pass so
nothing added while disconnected is missed.
"""

import json
import re
import threading
import time

from .common import utc

_ID = re.compile(r'[a-fA-F0-9-]{32,36}')


def queue_changes(db, frame):
    data = frame.get('Data') or {}
    if frame.get('MessageType') != 'LibraryChanged' or not isinstance(data, dict):
        return False
    changes = {}
    for field, action in (('ItemsAdded', 'upsert'), ('ItemsUpdated', 'upsert'), ('ItemsRemoved', 'hide')):
        values = data.get(field)
        for item_id in values if isinstance(values, list) else []:
            if isinstance(item_id, str) and _ID.fullmatch(item_id):
                changes[item_id] = action
    for item_id, action in changes.items():
        db.execute('INSERT INTO pending_changes VALUES(?,?,?) ON CONFLICT(item_id) DO UPDATE SET '
                   'action=excluded.action, seen_utc=excluded.seen_utc', (item_id, action, utc()))
    # Folder-level notifications don't list items: ask for a catch-up pass.
    return bool(data.get('FoldersAddedTo') or data.get('FoldersRemovedFrom'))


class EventListener:
    def __init__(self, url_factory):
        self.url_factory = url_factory
        self.connected = False
        self._frames = []
        self._lock = threading.Lock()
        self._catchup = False
        self.received = 0

    def take_reconnect(self):
        with self._lock:
            wanted, self._catchup = self._catchup, False
        return wanted

    def flush_into(self, db):
        with self._lock:
            frames, self._frames = self._frames, []
        catchup = False
        for frame in frames:
            catchup |= queue_changes(db, frame)
        if frames:
            db.commit()
        if catchup:
            with self._lock:
                self._catchup = True

    def run_forever(self):
        from websockets.sync.client import connect  # only needed in the service
        backoff = 1
        while True:
            try:
                with connect(self.url_factory(), open_timeout=15, close_timeout=5, max_size=8 * 1024 * 1024) as ws:
                    self.connected = True
                    backoff = 1
                    with self._lock:
                        self._catchup = True   # anything missed while disconnected
                    interval, last = 30.0, time.monotonic()
                    while True:
                        try:
                            message = ws.recv(timeout=5)
                        except TimeoutError:
                            message = None
                        if message:
                            frame = json.loads(message)
                            kind = frame.get('MessageType')
                            if kind == 'ForceKeepAlive' and isinstance(frame.get('Data'), (int, float)):
                                interval = max(5.0, frame['Data'] / 2)
                            elif kind == 'LibraryChanged':
                                self.received += 1
                                with self._lock:
                                    self._frames.append(frame)
                        if time.monotonic() - last >= interval:
                            ws.send(json.dumps({'MessageType': 'KeepAlive'}))
                            last = time.monotonic()
            except Exception:  # network drops, server restarts, auth expiry: reconnect
                pass
            self.connected = False
            time.sleep(backoff)
            backoff = min(backoff * 2, 60)
