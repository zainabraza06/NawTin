import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nawtin/app_router.dart';
import 'package:nawtin/features/online/debug/online_debug_screen.dart';
import 'package:nawtin/features/splash/splash_screen.dart';
import 'package:nawtin/services/online/auth_provider.dart';
import 'package:nawtin/services/online/online_config.dart';
import 'package:nawtin/services/prefs_store.dart';

void main() {
  group('server address', () {
    test('release builds accept wss:// only', () {
      expect(OnlineConfig.parse('wss://naw-tin.run.app/ws', release: true).isAvailable, isTrue);
      final plain = OnlineConfig.parse('ws://naw-tin.run.app/ws', release: true);
      expect(plain.isAvailable, isFalse);
      expect(plain.problem, contains('wss'));
      for (final bad in ['http://x.example/ws', 'https://x.example/ws', 'ftp://x', 'naw-tin', '', 'wss://']) {
        expect(OnlineConfig.parse(bad, release: true).isAvailable, isFalse, reason: bad);
      }
    });

    test('debug builds also allow ws:// to a local server', () {
      expect(OnlineConfig.parse('ws://10.0.2.2:8080/ws', release: false).url!.host, '10.0.2.2');
      expect(OnlineConfig.parse('wss://x.example/ws', release: false).isAvailable, isTrue);
      expect(OnlineConfig.parse('http://x', release: false).isAvailable, isFalse);
    });

    test('a release build with no address is unavailable, never a silent default', () {
      final c = OnlineConfig.fromEnvironment(release: true);
      expect(c.isAvailable, isFalse);
      expect(c.problem, isNotNull);
    });

    test('a release build refuses an insecure override too', () {
      expect(OnlineConfig.fromEnvironment(release: true, override: 'ws://evil.example/ws').isAvailable, isFalse);
      expect(OnlineConfig.fromEnvironment(release: true, override: 'wss://good.example/ws').isAvailable, isTrue);
    });

    test('debug defaults: the Android emulator reaches the host at 10.0.2.2, others at localhost', () {
      final android = OnlineConfig.fromEnvironment(release: false, platform: TargetPlatform.android, web: false);
      expect(android.url.toString(), 'ws://10.0.2.2:8080/ws');
      final ios = OnlineConfig.fromEnvironment(release: false, platform: TargetPlatform.iOS, web: false);
      expect(ios.url.toString(), 'ws://localhost:8080/ws');
      final web = OnlineConfig.fromEnvironment(release: false, platform: TargetPlatform.android, web: true);
      expect(web.url!.host, 'localhost');
    });

    test('the override from the debug console beats the default', () {
      final c = OnlineConfig.fromEnvironment(release: false, override: 'ws://192.168.1.20:8080/ws');
      expect(c.url!.host, '192.168.1.20');
    });
  });

  group('the fake sign-in exists in debug builds only', () {
    test('a release build can never obtain a fake token', () async {
      final store = MemoryPrefsStore()..write('debug.uid', 'sneaky');
      final auth = createAuth(debug: false, store: store, random: Random(1));
      expect(auth, isA<UnavailableAuth>());
      expect(auth.debugUid, isNull);
      await expectLater(auth.idToken(), throwsA(isA<AuthUnavailable>()));
    });

    test('a debug build gets test:<uid>, stable for the install', () async {
      final store = MemoryPrefsStore();
      final a = createAuth(debug: true, store: store, random: Random(1));
      final b = createAuth(debug: true, store: store, random: Random(2));
      expect(a, isA<DebugFakeAuth>());
      expect(await a.idToken(), startsWith('test:dev-'));
      expect(a.debugUid, b.debugUid, reason: 'saved on the device');
    });

    test('a real provider (Firebase, next stage) wins over the fake in any build', () async {
      final real = _Real();
      expect(createAuth(debug: true, store: MemoryPrefsStore(), random: Random(1), real: real), same(real));
      expect(createAuth(debug: false, store: MemoryPrefsStore(), random: Random(1), real: real), same(real));
    });

    test('the debug console is not reachable when the build is not a debug build', () {
      expect(pageFor(Routes.onlineDebug, debugBuild: false), isA<SplashScreen>(),
          reason: 'falls through to the normal fallback, never the console');
      expect(debugPageFor(Routes.onlineDebug, debugBuild: false), isNull);
      expect(pageFor(Routes.onlineDebug, debugBuild: true), isA<OnlineDebugScreen>());
      expect(debugPageFor(Routes.home), isNull, reason: 'normal pages are not debug pages');
    });
  });

  group('project configuration', () {
    test('Android: cleartext is forbidden in the main manifest and allowed in debug only', () {
      final main = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final debug = File('android/app/src/debug/AndroidManifest.xml').readAsStringSync();
      expect(main, contains('android:usesCleartextTraffic="false"'));
      expect(main, isNot(contains('usesCleartextTraffic="true"')));
      expect(debug, contains('android:usesCleartextTraffic="true"'));
      final release = File('android/app/src/release/AndroidManifest.xml');
      expect(release.existsSync(), isFalse, reason: 'nothing overrides the main manifest for release');
    });

    test('the Firebase client config is kept out of version control', () {
      final ignore = File('.gitignore').readAsStringSync();
      expect(ignore, contains('google-services.json'));
      expect(ignore, contains('GoogleService-Info.plist'));
    });

    test('the package name matches the Firebase app, if the file is present on this machine', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "com.zainab.nawtin"'));
      expect(gradle, contains('namespace = "com.zainab.nawtin"'));
      expect(File('android/app/src/main/kotlin/com/zainab/nawtin/MainActivity.kt').readAsStringSync(),
          startsWith('package com.zainab.nawtin'));
      final gs = File('android/app/google-services.json');
      if (gs.existsSync()) {
        final j = jsonDecode(gs.readAsStringSync()) as Map;
        expect((j['project_info'] as Map)['project_id'], 'nawtin-41c14');
        final pkgs = [for (final c in j['client'] as List) (c as Map)['client_info']['android_client_info']['package_name']];
        expect(pkgs, contains('com.zainab.nawtin'));
      }
    });
  });
}

class _Real implements AuthTokenProvider {
  @override
  String? get debugUid => null;
  @override
  Future<String> idToken({bool forceRefresh = false}) async => 'real-token';
}
