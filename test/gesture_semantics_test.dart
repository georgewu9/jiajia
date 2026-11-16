import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Flutter 3.47.9 手势语义回归（画布 detector 依赖这些行为，改动需回归）：
/// 1. 单 detector 同挂 onScale* + onTapUp + onDoubleTapDown 可行（scale 是 pan 超集）。
/// 2. 子节点是"无 child 的 CustomPaint"时，detector 区域不可命中，
///    单指 scale/pan 事件到不了识别器 → 画布必须给 CustomPaint 加 SizedBox.expand()。
/// 3. 挂了 onDoubleTapDown 后，单指 tap 要等 ~300ms 双击窗口才触发 onTapUp；
///    双击需两次 tap 间隔 <300ms（测试里用 100ms）。
class _Dot extends CustomPainter {
  const _Dot();
  @override
  void paint(Canvas c, Size s) {}
  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

void main() {
  testWidgets('单指 drag 触发 onScale（n=1）', (tester) async {
    var ev = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: const ValueKey('cv'),
      onScaleStart: (d) => ev.add('s1 n=${d.pointerCount}'),
      onScaleUpdate: (d) => ev.add('sU'),
      onScaleEnd: (d) => ev.add('sE'),
      child: const CustomPaint(painter: _Dot(), child: SizedBox.expand()),
    ))));
    await tester.pump();
    await tester.drag(find.byKey(const ValueKey('cv')), const Offset(300, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(ev.first, 's1 n=1');
    expect(ev.contains('sU'), true, reason: '应有 scale update');
    expect(ev.last, 'sE');
  });

  testWidgets('双击（两次 tap 间隔 100ms）触发 onDoubleTapDown', (tester) async {
    var ev = <String>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: GestureDetector(
      behavior: HitTestBehavior.opaque,
      key: const ValueKey('cv'),
      onTapUp: (d) => ev.add('tap'),
      onDoubleTapDown: (d) => ev.add('DBL'),
      onScaleStart: (d) => ev.add('s1'),
      child: const CustomPaint(painter: _Dot(), child: SizedBox.expand()),
    ))));
    await tester.pump();
    final c = tester.getCenter(find.byKey(const ValueKey('cv')));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tapAt(c);
    await tester.pump(const Duration(milliseconds: 400));
    expect(ev.contains('DBL'), true, reason: '双击应触发 onDoubleTapDown');
  });
}
