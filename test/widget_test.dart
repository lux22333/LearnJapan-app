import 'package:flutter_test/flutter_test.dart';

import 'package:learn_japan_flutter/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    await tester.pumpWidget(const LearnJapanApp());
    expect(find.text('标日学习'), findsOneWidget);
  });
}
