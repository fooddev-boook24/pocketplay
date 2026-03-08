// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pocketplay/app/pocketplay_app.dart';

void main() {
  testWidgets('home shelves render', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: PocketPlayApp()));
    await tester.pumpAndSettle();

    expect(find.text('PocketPlay'), findsOneWidget);
    expect(find.text('今日のおすすめ'), findsOneWidget);
    expect(find.text('パーティーゲーム'), findsOneWidget);
  });
}
