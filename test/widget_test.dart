import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_test/flutter_test.dart';

import 'package:jiajia/main.dart';

void main() {
  testWidgets('App 冒烟：画户型页可构建', (tester) async {
    await tester.pumpWidget(ProviderScope(child: JiajiaApp(errNotif: ValueNotifier<String?>(null))));
    expect(find.text('画户型'), findsOneWidget);
  });
}
