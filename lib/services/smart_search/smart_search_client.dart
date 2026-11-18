import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../connection/connection.dart';
import '../../media/media_item.dart';
import '../../media/media_browser_dialect.dart';
import '../../utils/app_logger.dart';

/// Client for the household smart-search service (`smartsearch/` in this
/// repository): a LAN index of one Jellyfin server that understands requests
/// such as "sci fi shows over 8" and describes-the-plot searches.
///
/// It needs no setup. The service runs on the Jellyfin host at [port] and is
/// only used when its `/v1/ping` reports the same server id as the connection.
/// Requests carry the connection's own Jellyfin token, which the service
/// checks with Jellyfin; items are then loaded through the normal Jellyfin
/// client, so a profile only ever sees titles Jellyfin lets it see.
///
/// Every failure is quiet and fast: callers fall back to ordinary search.
class SmartSearchClient {
  SmartSearchClient({http.Client Function()? httpClientFactory, DateTime Function()? clock})
    : _httpClientFactory = httpClientFactory ?? http.Client.new,
      _clock = clock ?? DateTime.now;

  static const int port = 8787;
  static const Duration probeTimeout = Duration(milliseconds: 900);
  static const Duration instantTimeout = Duration(milliseconds: 1500);
  static const Duration smartTimeout = Duration(seconds: 25);
  static const Duration _availableFor = Duration(minutes: 10);
  static const Duration _unavailableFor = Duration(minutes: 1);

  final http.Client Function() _httpClientFactory;
  final DateTime Function() _clock;
  final Map<String, ({bool available, DateTime until})> _probes = {};
  final Map<String, Future<bool>> _inFlight = {};

  /// Service base URL for [connection]: same host as Jellyfin, port [port].
  static Uri? endpointFor(JellyfinConnection connection) {
    if (connection.dialect != MediaBrowserDialect.jellyfin) return null;
    final base = Uri.tryParse(connection.baseUrl);
    if (base == null || !base.hasAuthority || base.host.isEmpty) return null;
    if (base.scheme != 'http' && base.scheme != 'https') return null;
    return Uri(scheme: 'http', host: base.host, port: port);
  }

  static String _normaliseServerId(String value) => value.replaceAll('-', '').toLowerCase();

  /// Whether the smart index for this exact server is reachable. Cached.
  Future<bool> isAvailable(JellyfinConnection connection) {
    final endpoint = endpointFor(connection);
    if (endpoint == null) return Future.value(false);
    final key = '${connection.id}@$endpoint';
    final cached = _probes[key];
    if (cached != null && _clock().isBefore(cached.until)) return Future.value(cached.available);
    return _inFlight[key] ??= _probe(connection, endpoint)
        .then((available) {
          _probes[key] = (available: available, until: _clock().add(available ? _availableFor : _unavailableFor));
          return available;
        })
        .whenComplete(() {
          // A block, not `=> remove(key)`: returning the removed future would
          // make this future wait on itself.
          _inFlight.remove(key);
        });
  }

  /// Whether a recent probe found the index for [connection] (no network).
  bool knownAvailable(JellyfinConnection connection) {
    final endpoint = endpointFor(connection);
    if (endpoint == null) return false;
    final cached = _probes['${connection.id}@$endpoint'];
    return cached != null && cached.available && _clock().isBefore(cached.until);
  }

  /// Forget a cached "available" after a failed request, so the next search
  /// re-checks instead of waiting on a service that went away.
  void markUnavailable(JellyfinConnection connection) {
    final endpoint = endpointFor(connection);
    if (endpoint == null) return;
    _probes['${connection.id}@$endpoint'] = (available: false, until: _clock().add(_unavailableFor));
  }

  Future<bool> _probe(JellyfinConnection connection, Uri endpoint) async {
    final client = _httpClientFactory();
    try {
      final response = await client.get(endpoint.replace(path: '/v1/ping')).timeout(probeTimeout);
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body);
      final serverId = body is Map ? body['server_id'] : null;
      return body is Map &&
          body['ok'] == true &&
          serverId is String &&
          _normaliseServerId(serverId) == _normaliseServerId(connection.serverMachineId);
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Instant results: titles, understood filters and full text. No AI.
  Future<SmartSearchResponse> instant(JellyfinConnection connection, String query, {int limit = 40}) =>
      _get(connection, '/v1/search', {'q': query, 'limit': '$limit'}, instantTimeout);

  /// Meaning-based results (optionally with the model's title recall).
  /// [seriesId] searches only that show's episodes (the show page's Find).
  Future<SmartSearchResponse> smart(
    JellyfinConnection connection,
    String query, {
    int limit = 20,
    bool recall = true,
    String? seriesId,
  }) => _get(connection, '/v1/smart', {
    'q': query,
    'limit': '$limit',
    'recall': recall ? '1' : '0',
    'series': ?seriesId,
  }, smartTimeout);

  /// The highest IMDb-rated movies and shows in the index (Home's "Top rated
  /// you haven't watched"; the caller removes what the viewer has watched).
  Future<SmartSearchResponse> topRated(JellyfinConnection connection, {double minRating = 7.5, int limit = 80}) =>
      _get(connection, '/v1/top', {'min_rating': '$minRating', 'limit': '$limit'}, instantTimeout);

  /// Titles closest in meaning to [itemId] (an episode counts as its show),
  /// with the title of the show or movie they were matched against.
  Future<({String? sourceTitle, SmartSearchResponse response})> similar(
    JellyfinConnection connection,
    String itemId, {
    int limit = 40,
  }) async {
    final json = await _getJson(connection, '/v1/similar', {'id': itemId, 'limit': '$limit'}, instantTimeout);
    final source = json is Map ? json['source'] : null;
    return (
      sourceTitle: source is Map && source['title'] is String ? source['title'] as String : null,
      response: SmartSearchResponse.fromJson(json),
    );
  }

  /// Library titles for outside suggestions, in the given order: [refs] are
  /// `movie|show:imdb|tmdb|tvdb:<id>` (Simkl, Trakt) or `item:<id>` (Jellyfin).
  /// [seedId] keeps anime/cartoon libraries when the seed lives in one.
  Future<SmartSearchResponse> resolve(JellyfinConnection connection, List<String> refs, {String? seedId}) => _get(
    connection,
    '/v1/resolve',
    {'refs': refs.take(200).join(','), 'seed': ?seedId, 'limit': '100'},
    instantTimeout,
  );

  /// IMDb vote counts for library items (Jellyfin ids), from the index's
  /// copy of IMDb's public ratings. Items it does not know are left out.
  Future<Map<String, int>> votes(JellyfinConnection connection, List<String> itemIds) async {
    final json = await _getJson(connection, '/v1/votes', {'ids': itemIds.take(200).join(',')}, instantTimeout);
    final votes = json is Map ? json['votes'] : null;
    if (votes is! Map) return const {};
    return {
      for (final MapEntry(:key, :value) in votes.entries)
        if (key is String && value is num) key: value.toInt(),
    };
  }

  Future<SmartSearchResponse> _get(
    JellyfinConnection connection,
    String path,
    Map<String, String> parameters,
    Duration timeout,
  ) async => SmartSearchResponse.fromJson(await _getJson(connection, path, parameters, timeout));

  Future<Object?> _getJson(
    JellyfinConnection connection,
    String path,
    Map<String, String> parameters,
    Duration timeout,
  ) async {
    final endpoint = endpointFor(connection);
    if (endpoint == null) throw const SmartSearchUnavailable('no smart-search endpoint for this server');
    final client = _httpClientFactory();
    try {
      final response = await client
          .get(
            endpoint.replace(path: path, queryParameters: parameters),
            headers: {'Authorization': 'MediaBrowser Token="${connection.accessToken}"', 'Accept': 'application/json'},
          )
          .timeout(timeout);
      if (response.statusCode != 200) {
        throw SmartSearchUnavailable('smart search returned HTTP ${response.statusCode}');
      }
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on SmartSearchUnavailable {
      rethrow;
    } catch (error) {
      appLogger.d('Smart search request failed', error: error);
      throw SmartSearchUnavailable('smart search request failed: ${error.runtimeType}');
    } finally {
      client.close();
    }
  }
}

final class SmartSearchUnavailable implements Exception {
  const SmartSearchUnavailable(this.message);

  final String message;

  @override
  String toString() => 'SmartSearchUnavailable: $message';
}

/// How sure the evidence check is that a smart result matches the request.
enum SmartSearchMatch {
  /// Two independent checks agree the synopsis supports the whole request.
  confirmed,

  /// Plausible but not confirmed; shown, never asserted.
  possible,

  /// Wrong show or person for an explicit request.
  rejected,

  /// Not checked (instant results, or checks unavailable).
  unchecked,
}

class SmartSearchHit {
  const SmartSearchHit({
    required this.id,
    required this.kind,
    required this.title,
    this.libraries = const [],
    this.copies = const [],
    this.match = SmartSearchMatch.unchecked,
    this.recalled = false,
  });

  final String id;
  final String kind;
  final String title;

  /// Library ids that hold this item (episodes inherit their show's). Empty
  /// when the index has not tagged it yet.
  final List<String> libraries;

  /// Other copies of the same title (e.g. a 4K and an HD library), with theirs.
  final List<({String id, List<String> libraries})> copies;
  final SmartSearchMatch match;

  /// Suggested from the language model's own knowledge of the title.
  final bool recalled;

  static SmartSearchHit? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final kind = json['kind'];
    if (id is! String || id.isEmpty || kind is! String) return null;
    return SmartSearchHit(
      id: id,
      kind: kind,
      title: json['title'] is String ? json['title'] as String : '',
      libraries: _strings(json['libraries']),
      copies: [
        if (json['copies'] case final List copies)
          for (final copy in copies)
            if (copy case {'id': final String copyId}) (id: copyId, libraries: _strings(copy['libraries'])),
      ],
      match: switch (json['match']) {
        'confirmed' => SmartSearchMatch.confirmed,
        'possible' => SmartSearchMatch.possible,
        'rejected' => SmartSearchMatch.rejected,
        _ => SmartSearchMatch.unchecked,
      },
      recalled: json['recalled'] == true,
    );
  }

  static List<String> _strings(Object? value) => [
    if (value is List)
      for (final entry in value)
        if (entry is String) entry,
  ];
}

class SmartSearchResponse {
  const SmartSearchResponse({
    required this.results,
    this.understood = const [],
    this.indexedLibraries = const {},
    this.unwatchedOnly = false,
  });

  /// The request asked for unwatched titles ("sci fi I haven't watched"). The
  /// index has no per-viewer watch state, so the app drops watched items.
  final bool unwatchedOnly;

  final List<SmartSearchHit> results;

  /// Libraries the index covers (movies and shows). Everything else on the
  /// server, such as music, still needs the server's own search.
  final Set<String> indexedLibraries;

  /// What the service understood, e.g. ["Shows", "Sci-Fi", "IMDb over 8"].
  final List<String> understood;

  factory SmartSearchResponse.fromJson(Object? json) {
    if (json is! Map) throw const SmartSearchUnavailable('malformed smart search response');
    return SmartSearchResponse(
      results: [
        if (json['results'] case final List rows)
          for (final row in rows) ?SmartSearchHit.fromJson(row),
      ],
      understood: SmartSearchHit._strings(json['understood']),
      indexedLibraries: SmartSearchHit._strings(json['indexed_libraries']).toSet(),
      unwatchedOnly: json['unwatched'] == true,
    );
  }

  /// Ids to load, in rank order, keeping only copies in a library the user has
  /// not hidden. An item stays when any of its libraries is visible; untagged
  /// items stay (Jellyfin still applies the user's own permissions).
  List<({String id, String? libraryId})> visibleIds(Set<String> hiddenLibraryIds) {
    final out = <({String id, String? libraryId})>[];
    final seen = <String>{};
    void add(String id, List<String> libraries) {
      if (!seen.add(id)) return;
      if (libraries.isEmpty) {
        out.add((id: id, libraryId: null));
        return;
      }
      final visible = libraries.where((l) => !hiddenLibraryIds.contains(l));
      if (visible.isNotEmpty) out.add((id: id, libraryId: visible.first));
    }

    for (final hit in results) {
      if (hit.match == SmartSearchMatch.rejected) continue;
      add(hit.id, hit.libraries);
      for (final copy in hit.copies) {
        add(copy.id, copy.libraries);
      }
    }
    return out;
  }
}

/// One row entry of meaning-based suggestions, already loaded for this user.
class SmartSuggestion {
  const SmartSuggestion({required this.item, required this.match, this.recalled = false});

  final MediaItem item;
  final SmartSearchMatch match;

  /// Suggested from the language model's knowledge of the title.
  final bool recalled;
}
