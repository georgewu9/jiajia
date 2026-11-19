import 'package:flutter_test/flutter_test.dart';
import 'package:jiajia/features/floorplan/domain/obj_parse.dart';
import 'package:jiajia/features/floorplan/state/lib_models_store.dart';

/// P2：外部 OBJ 导入的轻量解析（校验 + bbox，不做几何深解析）。
void main() {
  const cube = '''
# test cube
mtllib cube.mtl
o cube
v 0 0 0
v 2 0 0
v 2 0 1.2
v 0 0 1.2
v 0 0.5 0
v 2 0.5 0
v 2 0.5 1.2
v 0 0.5 1.2
usemtl wood
f 1 2 3
f 1 3 4
f 5 6 7
f 5 7 8
''';

  String manyFaces(int n) {
    final b = StringBuffer('v 0 0 0\nv 1 0 0\nv 0 1 0\n');
    for (var i = 0; i < n; i++) {
      b.writeln('f 1 2 3');
    }
    return b.toString();
  }

  test('合法 OBJ（v/f/usemtl）解析 + bbox 尺寸', () {
    final d = ObjParser.parse(cube);
    expect(d.vertexCount, 8);
    expect(d.faceCount, 4);
    expect(d.bboxW, closeTo(2.0, 1e-9)); // X 跨度
    expect(d.bboxD, closeTo(1.2, 1e-9)); // Z 跨度（深）
    expect(d.bboxH, closeTo(0.5, 1e-9)); // Y 跨度（高）
    expect(d.wMm, 2000);
    expect(d.dMm, 1200);
    expect(d.hMm, 500);
  });

  test('面数超限拒绝（>5000）', () {
    expect(
      () => ObjParser.parse(manyFaces(ObjParser.maxFaces + 1)),
      throwsA(
        isA<ObjParseException>().having(
          (e) => e.message,
          'message',
          contains('面数超限'),
        ),
      ),
    );
    // 恰好 5000 面仍可收（上限含等号）
    final ok = ObjParser.parse(manyFaces(ObjParser.maxFaces));
    expect(ok.faceCount, ObjParser.maxFaces);
  });

  test('体积超限拒绝（>300000 字符）', () {
    final big = 'v 0 0 0\n${'x' * (ObjParser.maxChars)}\n';
    expect(big.length, greaterThan(ObjParser.maxChars));
    expect(
      () => ObjParser.parse(big),
      throwsA(
        isA<ObjParseException>().having(
          (e) => e.message,
          'message',
          contains('过大'),
        ),
      ),
    );
  });

  test('无 f 拒绝 / 无 v 拒绝', () {
    expect(
      () => ObjParser.parse('v 0 0 0\nv 1 0 0\nv 0 1 0\n'),
      throwsA(
        isA<ObjParseException>().having(
          (e) => e.message,
          'message',
          contains('没有面'),
        ),
      ),
    );
    expect(
      () => ObjParser.parse('f 1 2 3\n'),
      throwsA(
        isA<ObjParseException>().having(
          (e) => e.message,
          'message',
          contains('没有顶点'),
        ),
      ),
    );
    // 空文本同样拒绝
    expect(() => ObjParser.parse(''), throwsA(isA<ObjParseException>()));
  });

  test('畸形行容忍：缺分量/非数字/未知指令/退化面 不炸也不计数', () {
    const txt = '''
v 0 0 0
v 1 0
v x y z
vn 0 1 0
vt 0 0
g group1
s 1
o thing
v 1 0 0
v 0 1 0
f 1 2
f 1 2 3
f 1//1 2//1 3//1
f 1/2/3 2/2/3 3/2/3
f -3 -2 -1
''';
    final d = ObjParser.parse(txt);
    expect(d.vertexCount, 3); // 3 条合法 v（含负数/缺分量的被跳过）
    expect(d.faceCount, 4); // 4 条合法面（f 1 2 被跳过）
    expect(d.bboxW, closeTo(1.0, 1e-9));
    expect(d.bboxH, closeTo(1.0, 1e-9));
  });

  test('所有顶点重合 → 包围盒为空 → 拒绝', () {
    expect(
      () => ObjParser.parse('v 1 1 1\nv 1 1 1\nv 1 1 1\nf 1 2 3\n'),
      throwsA(
        isA<ObjParseException>().having(
          (e) => e.message,
          'message',
          contains('包围盒为空'),
        ),
      ),
    );
  });

  test('模型 id = md5(objText) 前 10 位（已知向量 + 区分性）', () {
    expect(
      LibModel.idForText('abc'),
      '900150983c',
    ); // md5("abc")=900150983cd24fb0…
    expect(LibModel.idForText('abc').length, 10);
    expect(LibModel.idForText('abc'), isNot(LibModel.idForText('abd')));
    expect(LibModel.idForText(cube), LibModel.idForText(cube)); // 稳定
    // 空串也有确定值（避免 id 为空把整库搞坏）
    expect(LibModel.idForText('').length, 10);
  });
}
