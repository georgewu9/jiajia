import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:jiajia/main.dart';

void main() {
  testWidgets('App 冒烟：落地页可构建，「开始画户型」能进编辑器', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: JiajiaApp()));
    expect(find.text('开始画户型'), findsOneWidget);
    expect(find.text('3D 浏览'), findsOneWidget);
    await tester.tap(find.text('开始画户型'));
    await tester.pumpAndSettle();
    // 编辑器工具条出现
    expect(find.text('画墙'), findsOneWidget);
    expect(find.text('家具'), findsOneWidget);
  });
}
