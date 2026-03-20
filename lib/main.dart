import 'dart:developer' as dev;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
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
  runApp(const ProviderScope(child: PocketPlayApp()));
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
