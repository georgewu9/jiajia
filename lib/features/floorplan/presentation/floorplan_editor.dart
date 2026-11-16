import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../diag/boot_log.dart' show bootLog;
import '../domain/floor_plan.dart';
import '../domain/model_assets.dart';
import '../state/editor_doc.dart';
import '../../viewer3d/viewer3d_page.dart';

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
  Vec2? _wallStart; // 画墙拖拽起点
  Vec2? _wallCur; // 画墙拖拽实时终点
  final _cam = CameraCtrl();
  bool _draggingItem = false;
  Size _canvasSize = const Size(360, 480);

  @override
  void initState() {
    super.initState();
    bootLog.line('editor-init');
  }

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
            icon: const Icon(Icons.post_add, size: 20),
            tooltip: '新建户型',
            onPressed: () => _newPlan(plan),
          ),
          IconButton(
            icon: const Icon(Icons.auto_stories, size: 20),
            tooltip: '载入示例户型',
            onPressed: () => ref.read(editorDocProvider.notifier).mutate((p) {
              final s = samplePlan();
              p.name = s.name;
              p.importPlan(s);
            }),
          ),
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
          IconButton(
            icon: const Icon(Icons.view_in_ar, size: 20,
                color: JiajiaColors.accent),
            tooltip: '3D 浏览',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const Viewer3dPage())),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          _canvasSize = c.biggest;
          return Stack(
            children: [
              // 画布。手势分层：
              //  外层 = 双指缩放 + 单击/双击；内层 pan = 按工具分发
              //  （画墙工具：单指拖拽画墙；其它工具：单指平移画布/拖家具）
              GestureDetector(
                onScaleStart: (d) {
                  if (d.pointerCount == 1) _draggingItem = false;
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    _cam.zoom(d.focalPoint, d.scale);
                    _cam.panBy(d.focalPointDelta);
                    setState(() {});
                  }
                },
                onTapUp: (d) => _handleTap(d.localPosition, plan, c.biggest),
                onDoubleTapDown: (d) =>
                    _handleDoubleTap(d.localPosition, plan, c.biggest),
                child: GestureDetector(
                  onPanStart: (d) => _panStart(d.localPosition, plan),
                  onPanUpdate: (d) => _panUpdate(d, plan),
                  onPanEnd: (d) => _panEnd(plan),
                  onPanCancel: _panCancel,
                  child: CustomPaint(
                    painter: _PlanPainter(
                      plan: plan,
                      cam: _cam,
                      sel: _sel,
                      draft: _tool == EditorTool.wall
                          ? (_wallStart == null
                              ? null
                              : (_wallStart!, _wallCur ?? _wallStart!))
                          : null,
                    ),
                  ),
                ),
              ),
              // 空画布引导
              if (plan.walls.isEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: JiajiaColors.raised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: JiajiaColors.line),
                    ),
                    child: const Text(
                        '单指拖拽画墙（直线）· 端点自动吸附\n双击墙体：设尺寸 mm / 加门洞',
                        style:
                            TextStyle(color: JiajiaColors.text2, fontSize: 11),
                      ),
                  ),
                ),
              // 选中墙时：快捷操作条
              if (_sel?.type == 'wall')
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: _WallActionBar(
                    wallId: _sel!.id,
                    plan: plan,
                    onOpen: () => _openWallDialog(_sel!.id),
                    onErase: () => _eraseWall(_sel!.id),
                    onClear: () => setState(() => _sel = null),
                  ),
                ),
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
                    _toolChip('画墙', EditorTool.wall, Icons.draw,
                        () => _setTool(EditorTool.wall)),
                    _toolChip('选择', EditorTool.select, Icons.touch_app,
                        () => _setTool(EditorTool.select)),
                    _toolChip('开洞', EditorTool.opening, Icons.crop_square,
                        () => _setTool(EditorTool.opening)),
                    _toolChip('家具', EditorTool.furniture, Icons.inventory_2,
                        () => _setTool(EditorTool.furniture)),
                    _toolChip('素材', EditorTool.furniture, Icons.category,
                        _openModelSheet),
                    _toolChip('删除', EditorTool.erase, Icons.delete_outline,
                        () => _setTool(EditorTool.erase)),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _cam.fit(_canvasSize, plan),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Icon(Icons.fit_screen,
                            size: 18, color: JiajiaColors.text2),
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
                      for (final k in FurnitureCatalog.kinds)
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

  Widget _toolChip(
      String label, EditorTool t, IconData icon, VoidCallback onTap) {
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
        _wallStart = _wallCur = null;
      });

  // ---------------- 素材模型（原 app 内置 26 件，按分类选择） ----------------

  void _openModelSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JiajiaColors.surface,
      builder: (ctx) {
        int catIdx = 0;
        return StatefulBuilder(
          builder: (ctx2, setIt) {
            final cat = ModelAssets.categories[catIdx];
            final models = ModelAssets.ofCategory(cat);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.3,
              maxChildSize: 0.9,
              builder: (BuildContext c, ScrollController sc) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('素材模型 · ${models.length} 件',
                              style: const TextStyle(
                                  color: JiajiaColors.text1,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('原 app 内置',
                            style: TextStyle(
                                color: JiajiaColors.text2, fontSize: 11)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      controller: sc,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (var i = 0;
                            i < ModelAssets.categories.length;
                            i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(ModelAssets.categories[i],
                                  style: const TextStyle(fontSize: 12)),
                              selected: i == catIdx,
                              onSelected: (_) => setIt(() => catIdx = i),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3, mainAxisSpacing: 8),
                      itemCount: models.length,
                      itemBuilder: (_, j) {
                        final m = models[j];
                        return Tooltip(
                          message: '${m.w}×${m.d}×${m.h} m',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              _placeModel(m.id);
                              Navigator.pop(ctx2);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: JiajiaColors.raised,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: JiajiaColors.line),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.category,
                                      color: Color(0xFF000000 | m.color),
                                      size: 26),
                                  const SizedBox(height: 4),
                                  Text(m.label,
                                      style: const TextStyle(
                                          color: JiajiaColors.text1,
                                          fontSize: 12)),
                                  Text(
                                      '${m.w.toStringAsFixed(2)}×'
                                      '${m.d.toStringAsFixed(2)}×'
                                      '${m.h.toStringAsFixed(2)}m',
                                      style: TextStyle(
                                          color: JiajiaColors.text2,
                                          fontSize: 9)),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _placeModel(String mid) {
    final asset = ModelAssets.byId(mid);
    if (asset == null) return;
    final center = _cam.toWorld(
        Offset(_canvasSize.width / 2, _canvasSize.height / 2));
    final plan = ref.read(editorDocProvider).plan;
    final pos = _snapPoint(center, plan);
    ref.read(editorDocProvider.notifier).mutate((p) {
      final id = p.newId('i');
      p.items[id] = FurnitureItem(
          id: id,
          kind: FurnitureKind.asset,
          pos: pos,
          modelId: mid);
      _sel = _Sel(id, 'item');
    });
    _toast('已放 ${asset.label}：2D 为占地框，切 3D 看真实形状');
  }

  // ---------------- 新建 / 保存 ----------------

  void _newPlan(FloorPlan plan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JiajiaColors.surface,
        title: const Text('新建户型',
            style: TextStyle(color: JiajiaColors.text1)),
        content: const Text('清空当前画布？（可撤销）',
            style: TextStyle(color: JiajiaColors.text2)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              ref.read(editorDocProvider.notifier).mutate((p) {
                p.name = '新建户型';
                p.walls.clear();
                p.openings.clear();
                p.items.clear();
              });
              _sel = null;
              _wallStart = _wallCur = null;
              _cam.pan = const Offset(60, 60);
              _cam.ppm = 90;
              setState(() {});
              Navigator.pop(context);
            },
            child: const Text('新建',
                style: TextStyle(color: JiajiaColors.accent)),
          ),
        ],
      ),
    );
  }

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

  // ---------------- 单指 pan（按工具分发） ----------------

  /// 端点吸附（半径 0.15m）优先，其次 0.1m 网格吸附。
  Vec2 _snapPoint(Vec2 w, FloorPlan plan) {
    for (final wall in plan.walls.values) {
      for (final e in [wall.a, wall.b]) {
        if (w.distanceTo(e) < 0.15) return e;
      }
    }
    final g = 0.1;
    return Vec2((w.dx / g).round() * g, (w.dy / g).round() * g);
  }

  void _panStart(Offset local, FloorPlan plan) {
    final world = _cam.toWorld(local);
    switch (_tool) {
      case EditorTool.wall:
        _wallStart = _snapPoint(world, plan);
        _wallCur = _wallStart;
        setState(() {});
      case EditorTool.select:
        final hit = _hitTest(plan, world);
        _draggingItem =
            hit != null && hit.id == _sel?.id && hit.type == 'item';
        break;
      default:
        break;
    }
  }

  void _panUpdate(DragUpdateDetails d, FloorPlan plan) {
    switch (_tool) {
      case EditorTool.wall:
        _wallCur = _snapPoint(_cam.toWorld(d.localPosition), plan);
        setState(() {});
      case EditorTool.select:
        if (_draggingItem && _sel != null) {
          ref.read(editorDocProvider.notifier).mutate((p2) {
                final item = p2.items[_sel!.id];
                if (item == null) return;
                item.pos = item.pos +
                    Vec2(d.delta.dx / _cam.ppm, d.delta.dy / _cam.ppm);
              },
              record: false);
        } else {
          _cam.panBy(d.delta);
          setState(() {});
        }
      default:
        _cam.panBy(d.delta);
        setState(() {});
    }
  }

  void _panEnd(FloorPlan plan) {
    switch (_tool) {
      case EditorTool.wall:
        _commitWallDraft(plan);
      case EditorTool.select:
        if (_draggingItem) {
          ref.read(editorDocProvider.notifier).mutate((p2) {}, record: true);
          _draggingItem = false;
        }
      default:
        break;
    }
  }

  void _panCancel() {
    // 双指缩放抢走手势：取消画墙草稿 / 家具拖拽
    _wallStart = _wallCur = null;
    _draggingItem = false;
    setState(() {});
  }

  void _commitWallDraft(FloorPlan plan) {
    final s = _wallStart, c = _wallCur;
    _wallStart = _wallCur = null;
    if (s == null || c == null || s.distanceTo(c) < 0.05) return;
    HapticFeedback.lightImpact();
    ref.read(editorDocProvider.notifier).mutate((p) {
      final id = p.newId('w');
      p.walls[id] = Wall(id: id, a: s, b: c);
      _sel = _Sel(id, 'wall');
    });
    setState(() {});
  }

  // ---------------- 点击 / 双击 ----------------

  void _handleTap(Offset local, FloorPlan plan, Size canvas) {
    final notifier = ref.read(editorDocProvider.notifier);
    final world = _cam.toWorld(local);

    switch (_tool) {
      case EditorTool.wall:
        final hit = _hitWall(plan, world);
        setState(() => _sel = hit);
        break;
      case EditorTool.select:
        setState(() => _sel = _hitTest(plan, world));
        break;
      case EditorTool.opening:
        final wallSel = _hitWall(plan, world);
        if (wallSel != null) {
          _openWallDialog(wallSel.id);
        } else {
          _toast('点不到墙：先画一段墙，再点墙开洞');
        }
        break;
      case EditorTool.furniture:
        notifier.mutate((p) {
          final id = p.newId('i');
          p.items[id] = FurnitureItem(
            id: id,
            kind: _furnKind,
            pos: _snapPoint(world, plan),
            rotationDeg: 0,
          );
          _sel = _Sel(id, 'item');
        });
        break;
      case EditorTool.erase:
        final hit = _hitTest(plan, world);
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

  void _handleDoubleTap(Offset local, FloorPlan plan, Size canvas) {
    final hit = _hitWall(plan, _cam.toWorld(local));
    if (hit != null) {
      _openWallDialog(hit.id);
    } else {
      _cam.fit(canvas, plan);
      setState(() {});
    }
  }

  void _eraseWall(String wallId) {
    ref.read(editorDocProvider.notifier).mutate((p) {
      p.openings.removeWhere((_, o) => o.wallId == wallId);
      p.walls.remove(wallId);
      if (_sel?.id == wallId) _sel = null;
    });
    setState(() {});
  }

  void _toast(String m) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(m)));
  }

  /// 墙的完整编辑面板：尺寸 mm（长/墙高/墙厚）+ 开洞（门型/离墙距离/宽/高）。
  void _openWallDialog(String wallId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JiajiaColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (_) => _WallDialog(wallId: wallId),
    );
  }

  // ---------------- 命中检测 ----------------

  /// 点 p 在墙 a→b 上的投影参数 t∈[0,1]（越界则夹取）。
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

/// 选中墙时的快捷操作条。
class _WallActionBar extends StatelessWidget {
  final String wallId;
  final FloorPlan plan;
  final VoidCallback onOpen;
  final VoidCallback onErase;
  final VoidCallback onClear;

  const _WallActionBar({
    required this.wallId,
    required this.plan,
    required this.onOpen,
    required this.onErase,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final wall = plan.walls[wallId];
    if (wall == null) return const SizedBox.shrink();
    final opens = plan.openings.values
        .where((o) => o.wallId == wallId)
        .length;
    return Container(
      color: JiajiaColors.raised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '墙 $wallId · 长 ${toMm(wall.length)}mm · 厚 ${toMm(wall.thickness)} · 开洞 $opens',
                  style: const TextStyle(
                      fontSize: 11, color: JiajiaColors.text2),
                ),
              ),
              _act('加开洞', Icons.add_comment, onOpen),
              _act('删墙', Icons.delete_outline, onErase),
              _act('取消', Icons.close, onClear),
            ],
          ),
        ),
      ),
    );
  }

  Widget _act(String label, IconData icon, VoidCallback cb) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onPressed: cb,
        ),
      );
}

/// 墙编辑面板（双击墙 / 开洞工具 / 操作条 共用）：
///  ① 墙尺寸（mm）：长（缩放墙）/ 墙高 / 墙厚
///  ② 开洞：门型（门洞/单开门/双开门/移门/窗）+ 离墙距离 + 宽 + 高（+窗台）
class _WallDialog extends ConsumerStatefulWidget {
  final String wallId;
  const _WallDialog({required this.wallId});

  @override
  ConsumerState<_WallDialog> createState() => _WallDialogState();
}

class _WallDialogState extends ConsumerState<_WallDialog> {
  late final TextEditingController _lenC;
  late final TextEditingController _hC;
  late final TextEditingController _tC;
  late final TextEditingController _offC;
  late final TextEditingController _wC;
  late final TextEditingController _ohC;
  late final TextEditingController _sillC;

  DoorType _dt = DoorType.single;
  bool _asWindow = false;

  @override
  void initState() {
    super.initState();
    final wall =
        ref.read(editorDocProvider).plan.walls[widget.wallId];
    if (wall != null) {
      _lenC = TextEditingController(text: '${toMm(wall.length)}');
      _hC = TextEditingController(text: '${toMm(wall.height)}');
      _tC = TextEditingController(text: '${toMm(wall.thickness)}');
    }
    _offC = TextEditingController(text: '450');
    _wC = TextEditingController(text: '900');
    _ohC = TextEditingController(text: '2000');
    _sillC = TextEditingController(text: '900');
  }

  @override
  void dispose() {
    for (final c in [
      _lenC, _hC, _tC, _offC, _wC, _ohC, _sillC
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 切换门型 → 按家易量默认值预填宽/高。
  void _pickType(bool asWindow, DoorType dt) {
    setState(() {
      _asWindow = asWindow;
      _dt = dt;
      if (asWindow) {
        _wC.text = '1500';
        _ohC.text = '1500';
      } else {
        _wC.text = '${dt.defaultWidthMm}';
        _ohC.text = '${dt.defaultHeightMm}';
      }
    });
  }

  int? _parseMm(TextEditingController f, {int min = 1}) {
    final v = int.tryParse(f.text.trim());
    if (v == null || v < min) return null;
    return v;
  }

  void _applyWallDims() {
    final wall = ref.read(editorDocProvider).plan.walls[widget.wallId];
    if (wall == null) return;
    final lenMm = _parseMm(_lenC), hMm = _parseMm(_hC), tMm = _parseMm(_tC);
    if (lenMm == null || hMm == null || tMm == null) {
      _msg('尺寸需 ≥1 mm 的整数（单位 mm）');
      return;
    }
    ref.read(editorDocProvider.notifier).mutate((p) {
      // 缩放：固定 a 端，沿墙方向伸缩 b
      final lenM = fromMm(lenMm);
      wall.height = fromMm(hMm);
      wall.thickness = fromMm(tMm);
      final dir = wall.b.distanceTo(wall.a) > 1e-6
          ? ((wall.b - wall.a).normalized())
          : const Vec2(1, 0);
      wall.b = wall.a + dir * lenM;
      // 开洞随墙夹取，避免出界
      for (final o in p.openings.values) {
        if (o.wallId != wall.id) continue;
        if (o.width > lenM * 0.9) o.width = lenM * 0.9;
        if (o.offset > lenM - o.width) o.offset = lenM - o.width;
      }
    });
    _msg('墙尺寸已更新');
  }

  void _addOpening() {
    final plan = ref.read(editorDocProvider).plan;
    final wall = plan.walls[widget.wallId];
    if (wall == null) return;
    final offMm = _parseMm(_offC, min: 0);
    final wMm = _parseMm(_wC), hMm = _parseMm(_ohC);
    if (offMm == null || wMm == null || hMm == null) {
      _msg('开洞参数需 ≥0 的整数（单位 mm）');
      return;
    }
    ref.read(editorDocProvider.notifier).mutate((p) {
      final lenM = wall.length;
      var offM = fromMm(offMm), wM = fromMm(wMm);
      if (wM > lenM * 0.9) wM = lenM * 0.9;
      if (offM > lenM - wM) offM = lenM - wM;
      final id = p.newId('o');
      final sill = _asWindow ? fromMm(_parseMm(_sillC, min: 0) ?? 900) : 0.0;
      p.openings[id] = Opening(
        id: id,
        wallId: wall.id,
        kind: _asWindow ? OpeningKind.window : OpeningKind.door,
        doorType: _dt,
        offset: offM,
        width: wM,
        sill: sill,
        height: fromMm(hMm),
      );
    });
    _msg('已加开洞');
    if (context.mounted) Navigator.pop(context);
  }

  void _msg(String m) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = ref.read(editorDocProvider).plan;
    final wall = plan.walls[widget.wallId];
    if (wall == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('墙已不存在'),
      );
    }
    Widget mmField(String label, TextEditingController c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextFormField(
            controller: c,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: JiajiaColors.text1, fontSize: 14),
            decoration: InputDecoration(
              labelText: '$label (mm)',
              labelStyle: const TextStyle(color: JiajiaColors.text3),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 10),
              border: const OutlineInputBorder(),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(color: JiajiaColors.line)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                  borderSide:
                      const BorderSide(color: JiajiaColors.accent)),
            ),
            onChanged: (_) => setState(() {}),
          ),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (BuildContext c, ScrollController sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(16),
        children: [
            Text(
              '墙 ${wall.id} · 当前 长 ${toMm(wall.length)}mm · 厚 ${toMm(wall.thickness)}mm · 高 ${toMm(wall.height)}mm',
              style: const TextStyle(
                  color: JiajiaColors.accent,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text('墙尺寸',
                style: const TextStyle(
                    color: JiajiaColors.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                mmField('尺寸', _lenC),
                mmField('墙高', _hC),
                mmField('墙厚', _tC),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: _accentBtn('应用墙尺寸（固定起点缩放）', _applyWallDims),
            ),
            const Divider(height: 24),
            Text('开洞（门 / 窗）',
                style: const TextStyle(
                    color: JiajiaColors.text2,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final dt in DoorType.values)
                  ChoiceChip(
                    label: Text(dt.label,
                        style: const TextStyle(fontSize: 12)),
                    selected: !_asWindow && _dt == dt,
                    onSelected: (_) => _pickType(false, dt),
                  ),
                ChoiceChip(
                  label: const Text('窗', style: TextStyle(fontSize: 12)),
                  selected: _asWindow,
                  onSelected: (_) => _pickType(true, _dt),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                mmField('离墙距离', _offC),
                mmField('宽', _wC),
                mmField(_asWindow ? '窗高' : '门高', _ohC),
              ],
            ),
            if (_asWindow)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    mmField('窗台高', _sillC),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _accentBtn(_asWindow ? '加窗' : '加门', _addOpening),
                TextButton(
                  onPressed: () {
                    ref.read(editorDocProvider.notifier).mutate((p) {
                      p.openings.removeWhere((_, o) => o.wallId == wall.id);
                      p.walls.remove(wall.id);
                    });
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('删除此墙',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _accentBtn(String label, VoidCallback cb) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: JiajiaColors.accentSoft,
          foregroundColor: JiajiaColors.accent,
        ),
        onPressed: cb,
        child: Text(label,
            style: const TextStyle(fontSize: 13, color: JiajiaColors.accent)),
      );
}

// ---------------- 绘制 ----------------

class _PlanPainter extends CustomPainter {
  final FloorPlan plan;
  final CameraCtrl cam;
  final _Sel? sel;
  final (Vec2, Vec2)? draft; // 画墙拖拽中：(起点, 实时终点)

  _PlanPainter({
    required this.plan,
    required this.cam,
    required this.sel,
    this.draft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(JiajiaColors.bgBase, BlendMode.src);
    _paintGrid(canvas, size);
    _paintWalls(canvas);
    _paintItems(canvas);
    _paintSelection(canvas);
    if (draft != null) _paintWallDraft(canvas, draft!.$1, draft!.$2);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final w0 = cam.toWorld(Offset.zero);
    final w1 = cam.toWorld(Offset(size.width, size.height));
    final x0 = (w0.dx / 0.5).floor() * 0.5;
    final x1 = (w1.dx / 0.5).ceil() * 0.5;
    final y0 = (w0.dy / 0.5).floor() * 0.5;
    final y1 = (w1.dy / 0.5).ceil() * 0.5;

    for (double x = x0; x <= x1; x += 0.5) {
      final major = (x % 1.0).abs() < 0.01 || (x % 1.0 - 1).abs() < 0.01;
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
      final major = (y % 1.0).abs() < 0.01 || (y % 1.0 - 1).abs() < 0.01;
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
      // 实墙段（开洞分段）
      for (final s in _wallSegments(w)) {
        final t0 = s.$1, t1 = s.$2, isSolid = s.$3;
        if (!isSolid) continue;
        final dir = (p1 - p0);
        final len = dir.distance;
        if (len < 1e-3) continue;
        final u = Offset(dir.dx / len, dir.dy / len); // 单位方向
        final perp = Offset(-u.dy, u.dx);
        final half = w.thickness / 2 * cam.ppm;
        final p0o = p0 + perp * half, p0i = p0 - perp * half;
        final p1o = p1 + perp * half, p1i = p1 - perp * half;
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
        canvas.drawPath(
            path,
            Paint()
                ..color = sel?.id == w.id
                    ? JiajiaColors.wallSelected
                    : JiajiaColors.wall);
        // 尺寸标注（mm）
        final mid = (p0o + p0i + p1o + p1i) / 4;
        final tp = TextPainter(
            text: TextSpan(
                text: '${toMm(w.length)}mm',
                style: TextStyle(
                    color: sel?.id == w.id
                        ? JiajiaColors.accent
                        : JiajiaColors.text2,
                    fontSize: 10)),
            textDirection: TextDirection.ltr)
          ..layout();
        final labelPos =
            mid - Offset(0, half + 14); // 墙外侧（上侧）
        _paintLabelBg(canvas, labelPos, tp);
        tp.paint(canvas, labelPos);
      }
      // 开洞绘制（按门型）
      _paintOpenings(canvas, w, p0, p1);
    }
  }

  void _paintLabelBg(Canvas canvas, Offset p, TextPainter tp) {
    final paint = Paint()..color = JiajiaColors.bgBase;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(p.dx - 3, p.dy - 2, p.dx + tp.width + 3,
              p.dy + tp.height + 2),
          const Radius.circular(4)),
      paint,
    );
  }

  void _paintOpenings(Canvas canvas, Wall w, Offset p0, Offset p1) {
    final opens =
        plan.openings.values.where((o) => o.wallId == w.id).toList();
    final vec = p1 - p0;
    final len = vec.distance;
    if (len < 1e-3) return;
    final u = Offset(vec.dx / len, vec.dy / len); // 屏幕方向单位向量
    final n = Offset(-u.dy, u.dx); // 法向（左侧）
    final halfT = w.thickness / 2 * cam.ppm;

    for (final o in opens) {
      final t0 = (o.offset / w.length).clamp(0.0, 1.0);
      final t1 = ((o.offset + o.width) / w.length).clamp(0.0, 1.0);
      final hA = p0 + vec * t0; // 开洞起点（墙上）
      final hB = p0 + vec * t1; // 开洞终点
      final oPx = o.width * cam.ppm;

      final paint = Paint()
        ..color = JiajiaColors.opening
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      switch (o.kind) {
        case OpeningKind.window:
          // 双细线（玻璃）+ 标签
          final lo = n * halfT * 0.45, hi = -n * halfT * 0.45;
          canvas.drawLine(hA + lo, hB + lo, paint..strokeWidth = 1.5);
          canvas.drawLine(hA + hi, hB + hi, paint..strokeWidth = 1.5);
          _openLabel(canvas, (hA + hB) / 2 - n * (halfT + 12), o);
          break;

        case OpeningKind.door:
          switch (o.doorType) {
            case DoorType.doorway:
              // 门洞：中线虚线
              _dashed(canvas, hA, hB, paint, dash: 8, gap: 5, color: JiajiaColors.opening);
              _openLabel(canvas, (hA + hB) / 2 - n * (halfT + 12), o);
              break;

            case DoorType.single:
              // 铰链在 hA：门扇弧线（半径=宽），门扇画在开启 45° 位
              _doorSwing(canvas, hA, u, n, oPx, oPx, side: 1);
              _openLabel(canvas, hA - n * (halfT + 12), o);
              break;

            case DoorType.double:
              // 双扇：两端铰链，各半宽
              _doorSwing(canvas, hA, u, n, oPx, oPx / 2, side: 1);
              _doorSwing(canvas, hB, -u, n, oPx, oPx / 2, side: 1);
              _openLabel(canvas, (hA + hB) / 2 - n * (halfT + 12), o);
              break;

            case DoorType.sliding:
              // 推拉：两扇错层（沿法向 ±halfT*0.7），各占 55% 宽、错开 10%
              final s = halfT * 0.7;
              final a1 = hA + n * s;
              final b1 = hA + u * (oPx * 0.55) + n * s;
              final a2 = hB - n * s;
              final b2 = hB - u * (oPx * 0.45) - n * s;
              canvas.drawLine(a1, b1, paint);
              canvas.drawLine(a2, b2, paint);
              _openLabel(canvas, (hA + hB) / 2 - n * (halfT + 12), o);
              break;
          }
          break;
      }
    }
  }

  /// 门扇：[hinge] 铰链、[u] 墙方向、[n] 法向、[radius] 弧线半径（px）。
  void _doorSwing(
      Canvas canvas, Offset hinge, Offset u, Offset n, double _, double radius,
      {double side = 1}) {
    final paint = Paint()
      ..color = JiajiaColors.opening
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    // 门扇（开启 45°）：铰链 → 墙向+法向合成方向 * 半径
    final leafDir = (u * 0.7071 + n * 0.7071 * side);
    canvas.drawLine(hinge, hinge + leafDir * radius, paint);
    // 弧线：从墙向角 到 90° 扇形
    final a0 = math.atan2(u.dy, u.dx);
    final nvec = n * side;
    final a1 = math.atan2(nvec.dy, nvec.dx);
    canvas.drawArc(
        Rect.fromCircle(center: hinge, radius: radius),
        a0, a1 - a0, false, paint..strokeWidth = 1);
  }

  void _dashed(
      Canvas canvas, Offset a, Offset b, Paint p,
      {required double dash,
      required double gap,
      required Color color}) {
    final v = b - a;
    final L = v.distance;
    if (L < 1) return;
    final u = Offset(v.dx / L, v.dy / L);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    var s = 0.0;
    while (s < L) {
      final e = math.min(s + dash, L);
      canvas.drawLine(a + u * s, a + u * e, paint);
      s = e + gap;
    }
  }

  void _openLabel(Canvas canvas, Offset p, Opening o) {
    final tp = TextPainter(
        text: TextSpan(
            text: o.label,
            style: const TextStyle(
                color: JiajiaColors.opening,
                fontSize: 9,
                height: 1.2)),
        textDirection: TextDirection.ltr)
      ..layout();
    _paintLabelBg(canvas, p, tp);
    tp.paint(canvas, p);
  }

  /// 返回墙的分段：(t0, t1, isSolid)。开洞处 isSolid=false。
  List<(double, double, bool)> _wallSegments(Wall w) {
    final opens = plan.openings.values
        .where((o) => o.wallId == w.id)
        .map((o) => (
              (o.offset / w.length).clamp(0.0, 1.0),
              ((o.offset + o.width) / w.length).clamp(0.0, 1.0),
            ))
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));
    final out = <(double, double, bool)>[];
    double cursor = 0.0;
    for (final o in opens) {
      if (o.$2 <= o.$1) continue; // 零宽开洞跳过
      if (o.$1 > cursor) out.add((cursor, o.$1, true));
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
      canvas.drawRRect(rRect, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawRRect(
          rRect,
          Paint()
            ..color = color
            ..style = PaintingStyle.stroke
            ..strokeWidth = selected ? 2.5 : 1.5);
      final label = i.modelId == null
          ? FurnitureCatalog.labelOf(i.kind)
          : (ModelAssets.byId(i.modelId!)?.label ??
              FurnitureCatalog.labelOf(i.kind));
      final tp = TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(color: JiajiaColors.text1, fontSize: 10)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  void _paintSelection(Canvas canvas) {
    if (sel == null || sel!.type != 'wall') return;
    final w = plan.walls[sel!.id];
    if (w == null) return;
    final p0 = cam.toScreen(w.a);
    final p1 = cam.toScreen(w.b);
    final paint = Paint()
      ..color = JiajiaColors.accent
      ..strokeWidth = 3;
    canvas.drawLine(p0, p1, paint);
    for (final e in [p0, p1]) {
      canvas.drawCircle(e, 5, Paint()..color = JiajiaColors.accent);
    }
  }

  /// 画墙拖拽中：预览线 + 实时尺寸 mm。
  void _paintWallDraft(Canvas canvas, Vec2 a, Vec2 b) {
    final p0 = cam.toScreen(a);
    final p1 = cam.toScreen(b);
    final paint = Paint()
      ..color = JiajiaColors.accent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawLine(p0, p1, paint);
    for (final e in [p0, p1]) {
      canvas.drawCircle(
          e, 6,
          Paint()
            ..color = JiajiaColors.accent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
    final mid = (p0 + p1) / 2;
    final tp = TextPainter(
        text: TextSpan(
            text: '${toMm(a.distanceTo(b))}mm',
            style:
                const TextStyle(color: JiajiaColors.accent, fontSize: 12)),
        textDirection: TextDirection.ltr)
      ..layout();
    _paintLabelBg(canvas, mid - Offset(tp.width / 2, -20), tp);
    tp.paint(canvas, mid - Offset(tp.width / 2, -20));
  }

  @override
  bool shouldRepaint(_PlanPainter old) => true;
}
