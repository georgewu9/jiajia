import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('单 detector 只挂 onScale*：单指 drag 是否触发', (tester) async {
    var ev = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          key: const Key('cv'),
          onScaleStart: (d) => ev.add('sStart n=${d.pointerCount}'),
          onScaleUpdate: (d) => ev.add('sUpd n=${d.pointerCount}'),
          onScaleEnd: (d) => ev.add('sEnd'),
          onTapUp: (d) => ev.add('tap'),
          child: const ColoredBox(
              color: Colors.black,
              child: Center(child: Text('cv', style: TextStyle(color: Colors.white)))),
        ),
      ),
    ));
    await tester.pump();
    // 用最可靠的 finder+drag 驱动单指
    await tester.drag(find.byKey(const Key('cv')), const Offset(200, 0));
    await tester.pump();
    // ignore: avoid_print
    print('SCALE1: $ev');
  });

  testWidgets('对照：只挂 onPan*：单指 drag 是否触发', (tester) async {
    var ev = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GestureDetector(
          key: const Key('pv'),
          onPanStart: (d) => ev.add('pStart'),
          onPanUpdate: (d) => ev.add('pUpd'),
          onPanEnd: (d) => ev.add('pEnd'),
          onTapUp: (d) => ev.add('tap'),
          child: const ColoredBox(
              color: Colors.black,
              child: Center(child: Text('pv', style: TextStyle(color: Colors.white)))),
        ),
      ),
    ));
    await tester.pump();
    await tester.drag(find.byKey(const Key('pv')), const Offset(200, 0));
    await tester.pump();
    // ignore: avoid_print
    print('PAN1: $ev');
  });
}
