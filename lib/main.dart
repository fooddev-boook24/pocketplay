import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'features/home/home_screen.dart';

void main() {
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
