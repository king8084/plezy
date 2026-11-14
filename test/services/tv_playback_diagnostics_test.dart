import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/tv_playback_diagnostics.dart';

void main() {
  late Directory directory;
  late TvPlaybackDiagnostics diagnostics;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('plezy-diagnostics-test');
    diagnostics = TvPlaybackDiagnostics(directory: directory, fileBytes: 256, fileCount: 3);
  });

  tearDown(() async {
    await diagnostics.close();
    await diagnostics.flush();
    await directory.delete(recursive: true);
  });

  test('retains only bounded diagnostic vocabulary, never arbitrary log payloads', () async {
    diagnostics.record('tvOS playback startup: opening media at 42 ms');
    diagnostics.record('Apple TV remote: Home direct playback requested');
    diagnostics.record('tvOS display: switch END elapsedMs=2500');
    diagnostics.record('tvOS playback startup: primary media discovered at 75 ms');
    diagnostics.record('tvOS playback startup: file-loaded signal at 95 ms');
    diagnostics.record('GET http://server/video?token=secret');
    diagnostics.record('tvOS playback startup: http://server?token=secret at 10 ms');
    diagnostics.record('Apple TV remote: playback action source=presses detail=http://server');
    diagnostics.record('tvOS display: media title=private');
    final text = await diagnostics.read();
    expect(text, contains('opening media at 42 ms'));
    expect(text, contains('switch END'));
    expect(text, contains('primary media discovered at 75 ms'));
    expect(text, contains('file-loaded signal at 95 ms'));
    expect(text, isNot(contains('secret')));
    expect(text, isNot(contains('http://')));
    expect(text, isNot(contains('private')));
  });

  test('rotates within the disk budget and survives a new service instance', () async {
    for (var i = 0; i < 20; i++) {
      diagnostics.record('tvOS playback startup: opening media at $i ms');
    }
    await diagnostics.flush();
    final files = await directory.list().where((file) => file.path.endsWith('.log')).toList();
    expect(files.length, 3);
    for (final file in files) {
      expect(await File(file.path).length(), lessThanOrEqualTo(256));
    }
    final reopened = TvPlaybackDiagnostics(directory: directory, fileBytes: 256, fileCount: 3);
    final text = await reopened.read();
    expect(text, contains('at 19 ms'));
    expect(text, isNot(contains('at 0 ms')));
  });

  test('LAN endpoint requires opt-in and the private key, is read-only and can be stopped', () async {
    await diagnostics.initialize();
    expect(diagnostics.sharing, isFalse);
    await diagnostics.enableSharing();
    diagnostics.record('tvOS display: switch END elapsedMs=2500');
    final privateUrl = diagnostics.urlFor('127.0.0.1');
    final client = HttpClient();
    addTearDown(client.close);
    final denied = await (await client.getUrl(Uri.parse('http://127.0.0.1:${diagnostics.port}/diagnostics'))).close();
    expect(denied.statusCode, HttpStatus.forbidden);
    await denied.drain<void>();
    final allowed = await (await client.getUrl(Uri.parse(privateUrl))).close();
    expect(allowed.statusCode, HttpStatus.ok);
    expect(allowed.headers.value(HttpHeaders.cacheControlHeader), 'no-store');
    expect(await allowed.transform(const SystemEncoding().decoder).join(), contains('switch END'));
    final deniedWrite = await (await client.postUrl(Uri.parse(privateUrl))).close();
    expect(deniedWrite.statusCode, HttpStatus.methodNotAllowed);
    await deniedWrite.drain<void>();
    await diagnostics.close();
    final reopened = TvPlaybackDiagnostics(directory: directory);
    await reopened.initialize();
    expect(reopened.sharing, isTrue);
    expect(reopened.urlFor('127.0.0.1'), privateUrl);
    await reopened.disableSharing();
    final stopped = TvPlaybackDiagnostics(directory: directory);
    await stopped.initialize();
    expect(stopped.sharing, isFalse);
    await stopped.close();
  });
}
