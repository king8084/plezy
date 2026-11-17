"""Jellyfin (read-only metadata) and Ollama (embeddings) clients."""

import urllib.parse

from . import records
from .common import SearchError, api, endpoint, packed, sha, vector_blob


class Jellyfin:
    """Only GET metadata requests plus ordinary sign-in. No write endpoints."""

    def __init__(self, access, device_id, client='Plezy Smart Search'):
        self.base = endpoint(access['jellyfin_url'], jellyfin=True)
        self.username = access['jellyfin_username']
        self.password = access['jellyfin_password']
        self.auth = (f'MediaBrowser Client="{client}", Device="Smart search index", '
                     f'DeviceId="{device_id}", Version="2.0"')
        self.headers = None
        self.user_id = None
        self.token = None

    def login(self):
        data, _ = api(self.base, '/Users/AuthenticateByName', {'Authorization': self.auth},
                      {'Username': self.username, 'Pw': self.password})
        policy = data.get('User', {}).get('Policy', {})
        if policy.get('IsAdministrator') is not False or policy.get('EnableContentDeletion') is not False:
            raise SearchError('index account must be non-admin with deletion disabled')
        public, _ = api(self.base, '/System/Info/Public')
        self.user_id = data['User']['Id']
        self.token = data['AccessToken']
        self.headers = {'Authorization': self.auth + f', Token="{self.token}"'}
        source = {'server_id': public['Id'], 'user_id': self.user_id}
        source['key'] = sha(source['server_id'] + ':' + source['user_id'])
        return source

    def _items(self, **params):
        values = {'UserId': self.user_id, 'Recursive': 'true', 'EnableImages': 'false',
                  'EnableUserData': 'false', 'IsMissing': 'false', 'EnableTotalRecordCount': 'false', **params}
        path = '/Items?' + urllib.parse.urlencode(values)
        try:
            return api(self.base, path, self.headers, timeout=60)[0]
        except SearchError as error:
            if 'status 401' not in str(error):
                raise
            self.login()
            return api(self.base, path, self.headers, timeout=60)[0]

    def total(self, kind):
        return self._items(IncludeItemTypes=kind, Limit=0, EnableTotalRecordCount='true')['TotalRecordCount']

    def page(self, kind, start, limit):
        data = self._items(IncludeItemTypes=kind, SortBy='SortName,Id', SortOrder='Ascending',
                           StartIndex=start, Limit=limit, Fields=records.fields_for(kind),
                           EnableTotalRecordCount='true')
        return data.get('Items', []), data.get('TotalRecordCount', 0)

    def by_ids(self, ids):
        if not ids:
            return []
        rows = self._items(Ids=','.join(ids), Fields=records.PEOPLE_FIELDS, Limit=len(ids))
        return [r for r in rows.get('Items', []) if r.get('Id') in set(ids)]

    def changed_since(self, cutoff_iso, start, limit):
        data = self._items(IncludeItemTypes=','.join(records.KINDS), MinDateLastSaved=cutoff_iso,
                           SortBy='SortName,Id', SortOrder='Ascending', StartIndex=start, Limit=limit,
                           Fields=records.PEOPLE_FIELDS)
        return data.get('Items', [])

    UNSEARCHED_VIEWS = {'boxsets', 'playlists', 'music', 'musicvideos', 'livetv', 'books', 'photos'}

    def views(self):
        """The account's libraries (CollectionFolders), minus types search never shows."""
        data, _ = api(self.base, f'/Users/{self.user_id}/Views', self.headers, timeout=30)
        return [{'id': v['Id'], 'name': v.get('Name') or '', 'type': v.get('CollectionType')}
                for v in data.get('Items', []) if v.get('Id') and v.get('CollectionType') not in self.UNSEARCHED_VIEWS]

    def library_item_ids(self, library_id, start, limit):
        """Movie/Series ids under one library. (ParentId is honoured here, unlike with Ids=.)"""
        data = self._items(ParentId=library_id, IncludeItemTypes='Movie,Series', SortBy='SortName,Id',
                           StartIndex=start, Limit=limit, Fields='', EnableTotalRecordCount='true')
        return [r['Id'] for r in data.get('Items', []) if r.get('Id')], data.get('TotalRecordCount', 0)

    def socket_url(self, device_id):
        parts = urllib.parse.urlsplit(self.base)
        scheme = 'wss' if parts.scheme == 'https' else 'ws'
        query = urllib.parse.urlencode({'ApiKey': self.token, 'deviceId': device_id})
        return urllib.parse.urlunsplit((scheme, parts.netloc, parts.path + '/socket', query, ''))


class Ollama:
    """Embedding requests to the configured Ollama host, pinned to one model digest."""

    def __init__(self, access, model):
        self.base = endpoint(access['ollama_url'])
        self.headers = {'Authorization': 'Bearer ' + access['ollama_api_key']} if access.get('ollama_api_key') else {}
        self.model = model

    def available(self):
        try:
            tags, _ = api(self.base, '/api/tags', self.headers, timeout=5)
        except SearchError:
            return False
        for m in tags.get('models', []):
            if m.get('name') == self.model['name']:
                if m.get('digest') != self.model['digest'] or m.get('remote_host') or m.get('remote_model'):
                    raise SearchError('installed embedding model differs from the pinned digest')
                return True
        raise SearchError('pinned embedding model is not installed')

    def embed(self, texts, timeout=120, keep_alive='30m'):
        data, ms = api(self.base, '/api/embed', self.headers,
                       {'model': self.model['name'], 'input': texts, 'truncate': False, 'keep_alive': keep_alive},
                       timeout=timeout)
        vectors = data.get('embeddings', [])
        if len(vectors) != len(texts):
            raise SearchError('embedding count mismatch')
        return [vector_blob(v) for v in vectors], ms


def describe(source):
    return packed({k: source[k] for k in ('server_id', 'user_id')})
