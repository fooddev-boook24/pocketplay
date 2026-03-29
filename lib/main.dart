import 'dart:async';
import 'dart:developer' as dev;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'core/firebase_options.dart';
import 'features/home/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    dev.log('Firebase initialized', name: 'main');
  } catch (e) {
    dev.log('Firebase init failed: $e — using local data', name: 'main');
  }
  await _initAdMob();
  runApp(const ProviderScope(child: PocketPlayApp()));
}

/// UMP同意フロー → AdMob初期化
/// EU/EEAユーザーには同意フォームを表示し、canRequestAdsがtrueの場合のみ広告を初期化。
/// 非EU圏ではフォームは表示されず即座にinitializeへ進む。
Future<void> _initAdMob() async {
  // requestConsentInfoUpdateはコールバック式のためCompleterでawait可能にする
  final consentCompleter = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () async {
      // 成功: 必要ならフォームを表示（EU圏以外は即完了）
      try {
        await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
      } catch (e) {
        dev.log('UMP form error: $e', name: 'AdMob');
      }
      consentCompleter.complete();
    },
    (FormError error) {
      // 失敗: 同意取得できなくても続行（日本ユーザーには影響なし）
      dev.log('UMP update error: $error', name: 'AdMob');
      consentCompleter.complete();
    },
  );
  await consentCompleter.future;

  try {
    // 同意取得済み or 不要な地域の場合のみ広告SDKを初期化
    if (await ConsentInformation.instance.canRequestAds()) {
      await MobileAds.instance.initialize();
      dev.log('AdMob initialized', name: 'main');
    } else {
      dev.log('AdMob skipped: consent not granted', name: 'main');
    }
  } catch (e) {
    dev.log('AdMob init failed: $e', name: 'main');
  }
}

class PocketPlayApp extends StatelessWidget {
  const PocketPlayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PocketPlay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF1A0E00),
      ),
      home: const HomeScreen(),
    );
  }
}
