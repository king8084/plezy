import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../utils/app_logger.dart';

/// Bounded, app-private playback traces. LAN sharing is explicitly enabled in
/// View Logs. `/diagnostics` serves these traces; `/applog` serves the recent
/// in-memory application log, which is redacted as it is written (tokens,
/// server URLs and registered secrets never appear). The owner asked for the
/// application log so problems beyond playback start can be debugged.
class TvPlaybackDiagnostics {
  TvPlaybackDiagnostics({this.directory, this.fileBytes = 256 * 1024, this.fileCount = 4})
    : assert(fileBytes >= 256),
      assert(fileCount > 1);

  static final instance = TvPlaybackDiagnostics();
  final Directory? directory;
  final int fileBytes;
  final int fileCount;
  Directory? _root;
  HttpServer? _server;
  String? _key;
  Future<void>? _initialization;
  Future<void> _writes = Future.value();
  int _queued = 0;

  bool get sharing => _server != null;
  int? get port => _server?.port;

  // Only fixed diagnostic vocabulary and numeric measurements are retained.
  // In particular, errors, media titles/IDs, URLs and account tokens never
  // enter this store, even when they accompany a logger event.
  static bool accepts(String message) {
    if (message.length > 500) return false;
    return RegExp(
          r'^tvOS playback startup: (?:player initialized and playback data ready|display criteria preflight requested|'
          r'first-frame signal before display negotiation|display negotiation complete|first-frame UI ready|'
          r'opening media|media open returned|source resolution|primary media discovered|file-loaded signal) (?:at|took) [0-9]+ ms$',
        ).hasMatch(message) ||
        message == 'Apple TV remote: Home direct playback requested' ||
        RegExp(r'^Apple TV remote: playback action source=[a-z_]+ detail=[a-zA-Z]+$').hasMatch(message) ||
        RegExp(
          r'^tvOS display: (?:criteria SET range=(?:SDR|HDR10|HLG|Dolby Vision) fps=[0-9.]+ size=[0-9]+x[0-9]+|'
          r'criteria CLEAR reason=(?:invalid video dimensions|no display metadata|matching disabled|display criteria unavailable|format description failed|dispose)|'
          r'switch (?:START|END)|QMS SDR fast start wait skipped|wait observed completed switch remainingMs=[0-9]+|'
          r'wait pending=(?:true|false) inProgress=(?:true|false) extraDelayMs=[0-9]+|'
          r'wait complete reason=(?:end notification|start watchdog|end watchdog|manager unavailable|no switch in progress|'
          r'ended before wait \((?:already in progress|start notification|progress poll)\)) waited=(?:true|false) settleMs=[0-9]+) elapsedMs=[0-9]+$',
        ).hasMatch(message);
  }

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _root = directory ?? Directory('${(await getApplicationSupportDirectory()).path}/playback-diagnostics');
    await _root!.create(recursive: true);
    final state = File('${_root!.path}/sharing.json');
    if (await state.exists()) {
      try {
        final saved = jsonDecode(await state.readAsString()) as Map<String, dynamic>;
        final key = saved['key'];
        if (key is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
          _key = key;
          if (saved['enabled'] == true) await _listen();
        }
      } catch (_) {
        // A corrupt setting or unavailable port must never block playback.
      }
    }
  }

  void record(String message) {
    if (!accepts(message) || _queued >= 128) return;
    final line = '${DateTime.now().toUtc().toIso8601String()} $message\n';
    if (utf8.encode(line).length > fileBytes) return;
    _queued++;
    _writes = _writes.then((_) async {
      try {
        await initialize();
        final current = File('${_root!.path}/trace.0.log');
        final size = await current.exists() ? await current.length() : 0;
        if (size + utf8.encode(line).length > fileBytes) {
          for (var i = fileCount - 1; i >= 1; i--) {
            final older = File('${_root!.path}/trace.${i - 1}.log');
            final target = File('${_root!.path}/trace.$i.log');
            if (await target.exists()) await target.delete();
            if (await older.exists()) await older.rename(target.path);
          }
        }
        await current.writeAsString(line, mode: FileMode.append);
      } catch (_) {
        // Diagnostics are best effort and must not recursively log failures.
      } finally {
        _queued--;
      }
    });
  }

  Future<void> flush() => _writes;

  Future<String> read() async {
    await initialize();
    final result = Completer<String>();
    _writes = _writes.then((_) async {
      try {
        result.complete(await _readFiles());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<String> _readFiles() async {
    final result = StringBuffer('Plezy tvOS playback diagnostics v1\n');
    for (var i = fileCount - 1; i >= 0; i--) {
      final file = File('${_root!.path}/trace.$i.log');
      if (await file.exists()) result.write(await file.readAsString());
    }
    return result.toString();
  }

  Future<void> enableSharing() async {
    await initialize();
    _key ??= List.generate(32, (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _listen();
    await _saveSharing(true);
  }

  Future<void> _listen() async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 18765);
    _server!.listen((request) => unawaited(_handle(request)));
  }

  Future<void> _saveSharing(bool enabled) =>
      File('${_root!.path}/sharing.json').writeAsString(jsonEncode({'enabled': enabled, 'key': _key}), flush: true);

  Future<void> disableSharing() async {
    await initialize();
    await _saveSharing(false);
    await close();
  }

  /// Close the listener without changing the owner's saved preference.
  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
  }

  String urlFor(String address) => 'http://$address:$port/diagnostics?key=$_key';

  Future<List<String>> sharingUrls() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses) urlFor(address.address),
    ];
  }

  bool _authorized(String? candidate) {
    if (_key == null || candidate == null || candidate.length != _key!.length) return false;
    var difference = 0;
    for (var i = 0; i < candidate.length; i++) {
      difference |= candidate.codeUnitAt(i) ^ _key!.codeUnitAt(i);
    }
    return difference == 0;
  }

  /// The newest [lines] application log entries, oldest first. Entries are
  /// already redacted by [MemoryAwareLogPrinter] when they are recorded.
  static String applicationLog(int lines) {
    final entries = MemoryLogOutput.getLogs().take(lines.clamp(1, 5000)).toList().reversed;
    final out = StringBuffer();
    for (final entry in entries) {
      out
        ..write(entry.timestamp.toUtc().toIso8601String())
        ..write(' [')
        ..write(entry.level.name.toUpperCase())
        ..write('] ')
        ..writeln(entry.message);
      if (entry.error != null) out.writeln('  error: ${entry.error}');
    }
    return out.toString();
  }

  Future<void> _handle(HttpRequest request) async {
    try {
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      if (!_authorized(request.uri.queryParameters['key'])) {
        request.response.statusCode = HttpStatus.forbidden;
      } else if (request.uri.path != '/diagnostics' && request.uri.path != '/applog') {
        request.response.statusCode = HttpStatus.notFound;
      } else if (request.method != 'GET') {
        request.response.statusCode = HttpStatus.methodNotAllowed;
      } else {
        request.response.headers.contentType = ContentType.text;
        request.response.write(
          request.uri.path == '/applog'
              ? applicationLog(int.tryParse(request.uri.queryParameters['lines'] ?? '') ?? 1500)
              : await read(),
        );
      }
      await request.response.close();
    } catch (_) {
      try {
        await request.response.close();
      } catch (_) {}
    }
  }
}
