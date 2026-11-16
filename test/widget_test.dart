import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jiajia/main.dart';

void main() {
  testWidgets('App 冒烟：画户型页可构建', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JiajiaApp()));
    expect(find.text('画户型'), findsOneWidget);
  });
}
