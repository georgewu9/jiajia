import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../domain/floor_plan.dart';
import '../state/editor_doc.dart';

enum EditorTool { wall, select, opening, furniture, erase }

class _Sel {
  final String id;
  final String type; // wall | item | opening
  const _Sel(this.id, this.type);
  @override
  bool operator ==(Object o) => o is _Sel && o.id == id && o.type == type;
  @override
  int get hashCode => Object.hash(id, type);
}

/// 画布相机：世界(米) <-> 屏幕(px)。pan 平移，ppm 缩放。
class CameraCtrl {
  Offset pan = const Offset(80, 80);
  double ppm = 90; // pixels per meter

  Offset toScreen(Vec2 w) => Offset(w.dx * ppm + pan.dx, w.dy * ppm + pan.dy);
  Vec2 toWorld(Offset p) =>
      Vec2((p.dx - pan.dx) / ppm, (p.dy - pan.dy) / ppm);

  /// 双指缩放：围绕两点中点放大 [d]。
  void zoom(Offset center, double d) {
    final f = (ppm * d).clamp(20.0, 400.0) / ppm;
    // 保持 center 处的世界点不动
    final w = toWorld(center);
    ppm *= f;
    pan = center - Offset(w.dx * ppm, w.dy * ppm);
  }

  void panBy(Offset delta) => pan += delta;

  void fit(Size canvasSize, FloorPlan plan) {
    if (plan.walls.isEmpty) return;
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (final w in plan.walls.values) {
      minX = math.min(minX, math.min(w.a.dx, w.b.dx));
      maxX = math.max(maxX, math.max(w.a.dx, w.b.dx));
      minY = math.min(minY, math.min(w.a.dy, w.b.dy));
      maxY = math.max(maxY, math.max(w.a.dy, w.b.dy));
    }
    final mW = maxX - minX + 2, mH = maxY - minY + 2;
    ppm = math.min(canvasSize.width / mW, canvasSize.height / mH);
    pan = Offset(
      (canvasSize.width - mW * ppm) / 2 - minX * ppm,
      (canvasSize.height - mH * ppm) / 2 - minY * ppm,
    );
  }
}

class FloorplanEditorPage extends ConsumerStatefulWidget {
  const FloorplanEditorPage({super.key});

  @override
  ConsumerState<FloorplanEditorPage> createState() =>
      _FloorplanEditorPageState();
}

class _FloorplanEditorPageState
    extends ConsumerState<FloorplanEditorPage> {
  EditorTool _tool = EditorTool.wall;
  FurnitureKind _furnKind = FurnitureKind.sofa;
  _Sel? _sel;
  Vec2? _wallStart;
  final _cam = CameraCtrl();
  Offset _lastPan = Offset.zero;
  Offset _lastDrag = Offset.zero;
  bool _draggingItem = false;
  Size _canvasSize = const Size(360, 480);

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(editorDocProvider);
    final plan = doc.plan;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: JiajiaColors.text1)),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            tooltip: '撤销',
            onPressed: ref.read(editorDocProvider.notifier).canUndo
                ? () => ref.read(editorDocProvider.notifier).undo()
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            tooltip: '重做',
            onPressed: ref.read(editorDocProvider.notifier).canRedo
                ? () => ref.read(editorDocProvider.notifier).redo()
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 20),
            tooltip: '保存',
            onPressed: () => _save(context, plan),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          _canvasSize = c.biggest;
          return Stack(
            children: [
              // 画布
              GestureDetector(
                onScaleStart: (d) {
                  _lastPan = d.focalPoint;
                  _draggingItem = false;
                },
                onScaleUpdate: (d) {
                  _cam.zoom(d.focalPoint, d.scale);
                  _cam.panBy(d.focalPoint - _lastPan);
                  _lastPan = d.focalPoint;
                },
                onScaleEnd: (_) {},
                onPanStart: (p) {
                  _lastPan = p.localPosition;
                  _lastDrag = p.localPosition;
                  if (_tool == EditorTool.select && _sel != null && _sel!.type == 'item') {
                    _draggingItem = true;
                  }
                },
                onPanUpdate: (p) {
                  final local = p.localPosition;
                  if (_draggingItem) {
                    final delta = local - _lastDrag;
                    final s = _sel;
                    ref.read(editorDocProvider.notifier).mutate((p2) {
                      final item = s == null ? null : p2.items[s.id];
                      if (item == null) return;
                      item.pos = item.pos + Vec2(delta.dx / _cam.ppm, delta.dy / _cam.ppm);
                    }, record: false);
                    _lastDrag = local;
                  } else if (_tool == EditorTool.select && _sel == null) {
                    _cam.panBy(local - _lastPan);
                    _lastPan = local;
                  } else {
                    _cam.panBy(local - _lastPan);
                    _lastPan = local;
                  }
                },
                onPanEnd: (_) {
                  if (_draggingItem) {
                    ref.read(editorDocProvider.notifier).mutate((p2) {}, record: true);
                    _draggingItem = false;
                  }
                },
                onTapUp: (d) {
                  _handleTap(d.localPosition, plan, c.biggest);
                },
                onDoubleTap: () => _cam.fit(c.biggest, plan),
                child: CustomPaint(
                  painter: _PlanPainter(
                    plan: plan,
                    cam: _cam,
                    sel: _sel,
                    wallStart: _tool == EditorTool.wall ? _wallStart : null,
                  ),
                ),
              ),
              // 画墙时的起点提示
            ],
          );
        },
      ),
      bottomNavigationBar: Container(
        color: JiajiaColors.surface,
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 46,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    _toolChip('画墙', EditorTool.wall, Icons.edit, () => _setTool(EditorTool.wall)),
                    _toolChip('选择', EditorTool.select, Icons.touch_app, () => _setTool(EditorTool.select)),
                    _toolChip('开洞', EditorTool.opening, Icons.crop_square, () => _setTool(EditorTool.opening)),
                    _toolChip('家具', EditorTool.furniture, Icons.inventory_2, () => _setTool(EditorTool.furniture)),
                    _toolChip('删除', EditorTool.erase, Icons.delete_outline, () => _setTool(EditorTool.erase)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _cam.fit(_canvasSize, plan),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Icon(Icons.fit_screen, size: 18, color: JiajiaColors.text2),
                      ),
                    ),
                  ],
                ),
              ),
              if (_tool == EditorTool.furniture)
                SizedBox(
                  height: 42,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      for (final k in FurnitureKind.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(FurnitureCatalog.labelOf(k),
                                style: const TextStyle(fontSize: 12)),
                            selected: _furnKind == k,
                            onSelected: (_) => setState(() => _furnKind = k),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolChip(String label, EditorTool t, IconData icon, VoidCallback onTap) {
    final active = _tool == t;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon,
            size: 14, color: active ? JiajiaColors.accent : JiajiaColors.text2),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        backgroundColor: active ? JiajiaColors.accentSoft : JiajiaColors.raised,
        side: BorderSide(color: active ? JiajiaColors.accent : JiajiaColors.line),
        labelStyle: TextStyle(
            color: active ? JiajiaColors.accent : JiajiaColors.text1,
            fontSize: 13),
        onPressed: onTap,
      ),
    );
  }

  void _setTool(EditorTool t) =>
      setState(() {
        _tool = t;
        _sel = null;
        _wallStart = null;
      });

  Future<void> _save(BuildContext context, FloorPlan plan) async {
    try {
      await PlanStore().save(plan);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('保存失败')));
      }
    }
  }

  // ---------------- 交互 ----------------

  Vec2 _snap(Vec2 w) {
    final g = 0.1;
    return Vec2((w.dx / g).round() * g, (w.dy / g).round() * g);
  }

  void _handleTap(Offset local, FloorPlan plan, Size canvas) {
    final notifier = ref.read(editorDocProvider.notifier);
    final world = _snap(_cam.toWorld(local));

    switch (_tool) {
      case EditorTool.wall:
        final s = _wallStart;
        if (s == null) {
          _wallStart = world;
          setState(() {});
        } else {
          if (s.distanceTo(world) < 0.1) return;
          notifier.mutate((p) {
            final id = p.newId('w');
            p.walls[id] = Wall(id: id, a: s, b: world);
            _sel = _Sel(id, 'wall');
          });
          _wallStart = null;
        }
        break;
      case EditorTool.select:
        _sel = _hitTest(plan, _cam.toWorld(local));
        setState(() {});
        break;
      case EditorTool.opening:
        final wallSel = _hitWall(plan, _cam.toWorld(local));
        if (wallSel != null) {
          _askOpeningType(wallSel);
        } else {
          _toast('点不到墙：先用画墙工具画一段墙');
        }
        break;
      case EditorTool.furniture:
        notifier.mutate((p) {
          final id = p.newId('i');
          p.items[id] = FurnitureItem(
            id: id, kind: _furnKind, pos: world, rotationDeg: 0);
          _sel = _Sel(id, 'item');
        });
        break;
      case EditorTool.erase:
        final hit = _hitTest(plan, _cam.toWorld(local));
        if (hit == null) {
          _toast('没点到对象');
          return;
        }
        notifier.mutate((p) {
          if (hit.type == 'wall') {
            p.openings.removeWhere((_, o) => o.wallId == hit.id);
            p.walls.remove(hit.id);
          } else if (hit.type == 'item') {
            p.items.remove(hit.id);
          } else {
            p.openings.remove(hit.id);
          }
          if (_sel?.id == hit.id) _sel = null;
        });
        break;
    }
  }

  void _toast(String m) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(m)));
  }

  void _askOpeningType(_Sel sel) {
    final plan = ref.read(editorDocProvider).plan;
    final wall = plan.walls[sel.id];
    if (wall == null) return;
    // 开洞位置：默认放墙中点；MVP 不做精确 offset 编辑（M2 补）
    final off = (wall.length - 1.0) / 2;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JiajiaColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _OpeningChoice(
                  label: '门 0.9m',
                  kind: OpeningKind.door,
                  width: 0.9,
                  offset: off,
                  wallId: sel.id),
              _OpeningChoice(
                  label: '窗 2.0m',
                  kind: OpeningKind.window,
                  width: 2.0,
                  sill: 0.9,
                  offset: off,
                  wallId: sel.id),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- 命中检测 ----------------

  double? _paramOnWall(Wall wall, Vec2 p) {
    final abx = wall.b.dx - wall.a.dx;
    final aby = wall.b.dy - wall.a.dy;
    final len2 = abx * abx + aby * aby;
    if (len2 < 1e-6) return null;
    final t = ((p.dx - wall.a.dx) * abx + (p.dy - wall.a.dy) * aby) / len2;
    return t.clamp(0.0, 1.0);
  }

  _Sel? _hitWall(FloorPlan plan, Vec2 w) {
    double best = 0.3;
    _Sel? bestHit;
    for (final wall in plan.walls.values) {
      final t = _paramOnWall(wall, w);
      if (t == null) continue;
      final proj = wall.a + (wall.b - wall.a) * t;
      final d = w.distanceTo(proj);
      if (d < wall.thickness / 2 + 0.25 && d < best) {
        best = d;
        bestHit = _Sel(wall.id, 'wall');
      }
    }
    return bestHit;
  }

  _Sel? _hitTest(FloorPlan plan, Vec2 w) {
    for (final o in plan.openings.values) {
      final wall = plan.walls[o.wallId];
      if (wall == null) continue;
      final t = _paramOnWall(wall, w);
      if (t == null) continue;
      final off = wall.length * t;
      if ((off - o.offset).abs() < o.width / 2 + 0.05) {
        return _Sel(o.id, 'opening');
      }
    }
    final walls = _hitWall(plan, w);
    if (walls != null) return walls;
    for (final i in plan.items.values) {
      final (fw, fd) = i.footprint;
      final c = math.cos(i.rotationDeg * math.pi / 180);
      final s = math.sin(i.rotationDeg * math.pi / 180);
      final dx = w.dx - i.pos.dx;
      final dy = w.dy - i.pos.dy;
      final lx = dx * c + dy * s;
      final ly = -dx * s + dy * c;
      if (lx.abs() < fw / 2 + 0.08 && ly.abs() < fd / 2 + 0.08) {
        return _Sel(i.id, 'item');
      }
    }
    return null;
  }
}

class _OpeningChoice extends ConsumerWidget {
  final String label;
  final OpeningKind kind;
  final double width;
  final double offset;
  final double sill;
  final String wallId;

  const _OpeningChoice({
    required this.label,
    required this.kind,
    required this.width,
    required this.offset,
    required this.wallId,
    this.sill = 0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 14, color: JiajiaColors.text1)),
      backgroundColor: JiajiaColors.raised,
      side: const BorderSide(color: JiajiaColors.line),
      onPressed: () {
        ref.read(editorDocProvider.notifier).mutate((p) {
          final id = p.newId('o');
          p.openings[id] = Opening(
            id: id,
            wallId: wallId,
            kind: kind,
            offset: offset,
            width: width,
            sill: sill,
          );
        });
        if (context.mounted) Navigator.pop(context);
      },
    );
  }
}

// ---------------- 绘制 ----------------

class _PlanPainter extends CustomPainter {
  final FloorPlan plan;
  final CameraCtrl cam;
  final _Sel? sel;
  final Vec2? wallStart;

  _PlanPainter({
    required this.plan,
    required this.cam,
    required this.sel,
    required this.wallStart,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(JiajiaColors.bgBase, BlendMode.src);
    _paintGrid(canvas, size);
    _paintWalls(canvas);
    _paintItems(canvas);
    _paintSelection(canvas);
    if (wallStart != null) _paintWallStart(canvas, wallStart!);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final w0 = cam.toWorld(Offset.zero);
    final w1 = cam.toWorld(Offset(size.width, size.height));
    final x0 = (w0.dx / 0.5).floor() * 0.5;
    final x1 = (w1.dx / 0.5).ceil() * 0.5;
    final y0 = (w0.dy / 0.5).floor() * 0.5;
    final y1 = (w1.dy / 0.5).ceil() * 0.5;

    for (double x = x0; x <= x1; x += 0.5) {
      final major = (x / 1.0).roundToDouble() == x / 1.0 && (x % 1.0).abs() < 0.01;
      final px = cam.toScreen(Vec2(x, 0)).dx;
      final paint = Paint()
        ..color = major ? JiajiaColors.gridMajor : JiajiaColors.gridMinor
        ..strokeWidth = major ? 1.2 : 0.7;
      canvas.drawLine(Offset(px, 0), Offset(px, size.height), paint);
      if (major && x.abs() > 0.01) {
        final tp = TextPainter(
            text: TextSpan(
                text: '${(x / 1.0).round()}',
                style: const TextStyle(color: JiajiaColors.text3, fontSize: 9)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(px + 2, 2));
      }
    }
    for (double y = y0; y <= y1; y += 0.5) {
      final major = (y / 1.0).roundToDouble() == y / 1.0 && (y % 1.0).abs() < 0.01;
      final py = cam.toScreen(Vec2(0, y)).dy;
      final paint = Paint()
        ..color = major ? JiajiaColors.gridMajor : JiajiaColors.gridMinor
        ..strokeWidth = major ? 1.2 : 0.7;
      canvas.drawLine(Offset(0, py), Offset(size.width, py), paint);
      if (major && y.abs() > 0.01) {
        final tp = TextPainter(
            text: TextSpan(
                text: '${(y / 1.0).round()}m',
                style: const TextStyle(color: JiajiaColors.text3, fontSize: 9)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(2, py + 2));
      }
    }
  }

  void _paintWalls(Canvas canvas) {
    for (final w in plan.walls.values) {
      final p0 = cam.toScreen(w.a);
      final p1 = cam.toScreen(w.b);
      // 开洞分段
      final segs = _wallSegments(w);
      for (final s in segs) {
        final t0 = s.$1, t1 = s.$2;
        final isSolid = s.$3;
        final paint = Paint()
          ..strokeWidth = isSolid ? w.thickness * cam.ppm : 0
          ..color = isSolid ? JiajiaColors.wall : Colors.transparent
          ..strokeCap = StrokeCap.butt
          ..style = PaintingStyle.fill;
        // 厚墙：用矩形填充
        if (isSolid) {
          final dir = (Vec2(p1.dx - p0.dx, p1.dy - p0.dy)).normalized();
          final perp = Vec2(-dir.dy, dir.dx);
          final half = w.thickness / 2 * cam.ppm;
          final p0o = p0 + Offset(perp.dx * half, perp.dy * half);
          final p0i = p0 - Offset(perp.dx * half, perp.dy * half);
          final p1o = p1 + Offset(perp.dx * half, perp.dy * half);
          final p1i = p1 - Offset(perp.dx * half, perp.dy * half);
          // 只画 [t0,t1] 段
          final p0so = p0o + (p1o - p0o) * t0;
          final p0si = p0i + (p1i - p0i) * t0;
          final p1so = p0o + (p1o - p0o) * t1;
          final p1si = p0i + (p1i - p0i) * t1;
          final path = Path()
            ..moveTo(p0so.dx, p0so.dy)
            ..lineTo(p1so.dx, p1so.dy)
            ..lineTo(p1si.dx, p1si.dy)
            ..lineTo(p0si.dx, p0si.dy)
            ..close();
          canvas.drawPath(path, paint);
        }
      }
      // 开洞标记
      for (final o in plan.openings.values) {
        if (o.wallId != w.id) continue;
        final t = o.offset / w.length;
        final mid = p0 + (p1 - p0) * math.min(0.98, math.max(0.02, t));
        final paint = Paint()
          ..color = JiajiaColors.opening
          ..strokeWidth = 2;
        if (o.kind == OpeningKind.door) {
          // 门：画弧线
          final r = 0.9 * cam.ppm;
          canvas.drawArc(
              Rect.fromCircle(center: mid, radius: r),
              0, math.pi / 2, false, paint);
        } else {
          canvas.drawCircle(mid, 4, paint..style = PaintingStyle.stroke);
        }
      }
    }
  }

  /// 返回墙的分段：(t0, t1, isSolid)。开洞处 isSolid=false。
  List<(double, double, bool)> _wallSegments(Wall w) {
    final opens = plan.openings.values
        .where((o) => o.wallId == w.id)
        .map((o) => (
              o.offset / w.length, (o.offset + o.width) / w.length,
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <(double, double, bool)>[];
    double cursor = 0.0;
    for (final o in opens) {
      if (o.$1 > cursor) {
        out.add((cursor, o.$1, true));
      }
      out.add((o.$1, o.$2, false));
      cursor = o.$2;
    }
    if (cursor < 1.0) out.add((cursor, 1.0, true));
    if (out.isEmpty) out.add((0.0, 1.0, true));
    return out;
  }

  void _paintItems(Canvas canvas) {
    for (final i in plan.items.values) {
      final p = cam.toScreen(i.pos);
      final (fw, fd) = i.footprint;
      final w = fw * cam.ppm;
      final h = fd * cam.ppm;
      final selected = sel?.id == i.id;
      final color = selected ? JiajiaColors.accent : JiajiaColors.furniture;
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(i.rotationDeg * math.pi / 180);
      final rRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(4));
      canvas.drawRRect(
          rRect,
          Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawRRect(
          rRect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.5 : 1.5);
      // 标签
      final tp = TextPainter(
          text: TextSpan(
              text: FurnitureCatalog.labelOf(i.kind),
              style: TextStyle(color: JiajiaColors.text1, fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  void _paintSelection(Canvas canvas) {
    if (sel == null) return;
    if (sel!.type == 'wall') {
      final w = plan.walls[sel!.id];
      if (w == null) return;
      final p0 = cam.toScreen(w.a);
      final p1 = cam.toScreen(w.b);
      final paint = Paint()
        ..color = JiajiaColors.accent
        ..strokeWidth = 3;
      canvas.drawLine(p0, p1, paint);
      // 尺寸标注
      final mid = (p0 + p1) / 2;
      final tp = TextPainter(
          text: TextSpan(
              text: '${w.length.toStringAsFixed(2)}m',
              style: const TextStyle(color: JiajiaColors.accent, fontSize: 11)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - 18));
    }
  }

  void _paintWallStart(Canvas canvas, Vec2 start) {
    final p = cam.toScreen(start);
    canvas.drawCircle(
        p,
        5,
        Paint()
          ..color = JiajiaColors.accent
          ..style = PaintingStyle.fill);
    final tp = TextPainter(
        text: const TextSpan(
            text: '点第二点结束',
            style: TextStyle(color: JiajiaColors.accent, fontSize: 11)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(canvas, Offset(p.dx + 8, p.dy - 8));
  }

  @override
  bool shouldRepaint(_PlanPainter old) => true;
}
