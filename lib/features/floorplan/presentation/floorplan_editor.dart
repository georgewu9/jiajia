import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../diag/boot_log.dart' show bootLog;
import '../domain/floor_plan.dart';
import '../domain/model_assets.dart';
import '../domain/model_items.dart';
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
  Vec2 toWorld(Offset p) => Vec2((p.dx - pan.dx) / ppm, (p.dy - pan.dy) / ppm);

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

class _FloorplanEditorPageState extends ConsumerState<FloorplanEditorPage> {
  EditorTool _tool = EditorTool.wall;
  FurnitureKind _furnKind = FurnitureKind.sofa;
  _Sel? _sel;
  Vec2? _wallStart; // 画墙拖拽起点
  Vec2? _wallCur; // 画墙拖拽实时终点
  final _cam = CameraCtrl();
  bool _draggingItem = false;
  Size _canvasSize = const Size(360, 480);
  final GlobalKey _paintKey = GlobalKey();
  Offset? _downLocal; // 最近一次手指按下位置（画墙起点用它，避开 scale slop 偏移）
  bool _showAreas = false; // 面积标注开关
  String _roomsSig = '';
  List<RoomLoop> _rooms = const [];
  ModelSpec? _pendingModel; // 「模型」面板选中的待放置项（门/窗贴墙，柱/楼梯/台面摆地）
  int? _mergeFrom; // 合并房：待合并的房间下标（点相邻房间完成）

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
        title: Text(
          plan.name,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: JiajiaColors.text1,
          ),
        ),
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
            icon: const Icon(
              Icons.view_in_ar,
              size: 20,
              color: JiajiaColors.accent,
            ),
            tooltip: '3D 浏览',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const Viewer3dPage()),
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, c) {
          _canvasSize = c.biggest;
          return Stack(
            children: [
              // 画布。手势全部挂在同一个 GestureDetector（scale 是 pan 的超集）：
              //  单指 → 平移/画墙/拖家具（onScale* 的 pointerCount==1 分支）
              //  双指 → 缩放（pointerCount>=2 分支，接管时丢弃单指草稿）
              //  单击/双击 → 选中 / 墙面板
              // 坑①：同一 detector 不能既写 onPan* 又写 onScale*（框架断言 scale 是超集）
              // 坑②：拆成嵌套两层也不行——外层 scale 识别器会抢走单指拖拽（画墙无反应）
              GestureDetector(
                // 坑③（本 Bug 根因）：CustomPaint 无 child 时该 detector 区域不可命中，
                // 单指拖/画墙事件根本到不了识别器 → 加 SizedBox.expand() 撑满区域
                // + opaque 兜底（实测 3.47.9：仅 opaque 不够，必须有 child 区域）
                behavior: HitTestBehavior.opaque,
                key: const ValueKey('cv'),
                onScaleStart: (d) {
                  if (d.pointerCount == 1) {
                    _panStart(_toLocal(d.focalPoint), plan); // 按当前工具分发
                  }
                },
                onScaleUpdate: (d) {
                  if (d.pointerCount >= 2) {
                    _panCancel(); // 双指接管：丢弃单指草稿/家具拖拽
                    _cam.zoom(_toLocal(d.focalPoint), d.scale);
                    _cam.panBy(d.focalPointDelta);
                    setState(() {});
                  } else {
                    _panUpdateAt(
                      _toLocal(d.focalPoint),
                      d.focalPointDelta,
                      plan,
                    );
                  }
                },
                onScaleEnd: (d) {
                  _panEnd(plan);
                },
                onTapUp: (d) => _handleTap(d.localPosition, plan, c.biggest),
                onDoubleTapDown: (d) =>
                    _handleDoubleTap(d.localPosition, plan, c.biggest),
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (e) => _downLocal = e.localPosition,
                  child: CustomPaint(
                    key: _paintKey,
                    painter: _PlanPainter(
                      plan: plan,
                      cam: _cam,
                      sel: _sel,
                      draft: _tool == EditorTool.wall
                          ? (_wallStart == null
                                ? null
                                : (_wallStart!, _wallCur ?? _wallStart!))
                          : null,
                      rooms: _roomsOf(plan),
                      showAreas: _showAreas,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              // 空画布引导
              if (plan.walls.isEmpty)
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: JiajiaColors.raised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: JiajiaColors.line),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '单指拖拽画墙（直线）· 端点自动吸附 · 45°角锁定\n双击墙体：设尺寸 mm / 加门洞',
                          style: TextStyle(
                            color: JiajiaColors.text2,
                            fontSize: 11,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: TextButton(
                            onPressed: () => _openRoomDialog(),
                            child: const Text(
                              '输入尺寸 一键建房间 →',
                              style: TextStyle(
                                color: JiajiaColors.accent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
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
              // 选中房间时：拆/合/删 操作条（原 app 分房入口）
              if (_sel?.type == 'room')
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 64,
                  child: _RoomActionBar(
                    roomIdx: int.tryParse(
                            _sel!.id.replaceFirst('room:', '')) ??
                        0,
                    onSplit: () {
                      final i = _roomIndexOf();
                      if (i != null) _openSplitDialog(i);
                    },
                    onMerge: () {
                      final i = _roomIndexOf();
                      if (i != null) _armMerge(i);
                    },
                    onRemove: () {
                      final i = _roomIndexOf();
                      if (i != null) _removeRoom(i);
                    },
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
                    _toolChip(
                      '画墙',
                      EditorTool.wall,
                      Icons.draw,
                      () => _setTool(EditorTool.wall),
                    ),
                    _toolChip('建房', EditorTool.wall, Icons.room, () {
                      _setTool(EditorTool.wall);
                      _openRoomDialog();
                    }),
                    _areaChip,
                    _toolChip(
                      '选择',
                      EditorTool.select,
                      Icons.touch_app,
                      () => _setTool(EditorTool.select),
                    ),
                    _toolChip(
                      '开洞',
                      EditorTool.opening,
                      Icons.crop_square,
                      () => _setTool(EditorTool.opening),
                    ),
                    _toolChip(
                      '家具',
                      EditorTool.furniture,
                      Icons.inventory_2,
                      () => _setTool(EditorTool.furniture),
                    ),
                    _toolChip(
                      '素材',
                      EditorTool.furniture,
                      Icons.category,
                      _openModelSheet,
                    ),
                    _toolChip(
                      '模型',
                      EditorTool.furniture,
                      Icons.architecture,
                      _openModelItemsSheet,
                    ),
                    _toolChip(
                      '删除',
                      EditorTool.erase,
                      Icons.delete_outline,
                      () => _setTool(EditorTool.erase),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _cam.fit(_canvasSize, plan),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Icon(
                          Icons.fit_screen,
                          size: 18,
                          color: JiajiaColors.text2,
                        ),
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
                      if (_pendingModel != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ActionChip(
                            avatar: Icon(
                              Icons.touch_app,
                              size: 14,
                              color: JiajiaColors.accent,
                            ),
                            label: Text(
                              '放：${_pendingModel!.label} → 点${_pendingModel!.place == ModelPlace.wall ? '墙' : '画布'}（点「选择」结束）',
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: JiajiaColors.accentSoft,
                            side: const BorderSide(color: JiajiaColors.accent),
                          ),
                        )
                      else
                        for (final k in FurnitureCatalog.kinds)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                FurnitureCatalog.labelOf(k),
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: _furnKind == k,
                              onSelected: (_) =>
                                  setState(() => _furnKind = k),
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
    String label,
    EditorTool t,
    IconData icon,
    VoidCallback onTap,
  ) {
    final active = _tool == t;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(
          icon,
          size: 14,
          color: active ? JiajiaColors.accent : JiajiaColors.text2,
        ),
        label: Text(label, style: const TextStyle(fontSize: 13)),
        backgroundColor: active ? JiajiaColors.accentSoft : JiajiaColors.raised,
        side: BorderSide(
          color: active ? JiajiaColors.accent : JiajiaColors.line,
        ),
        labelStyle: TextStyle(
          color: active ? JiajiaColors.accent : JiajiaColors.text1,
          fontSize: 13,
        ),
        onPressed: onTap,
      ),
    );
  }

  void _setTool(EditorTool t) => setState(() {
    _tool = t;
    _sel = null;
    _wallStart = _wallCur = null;
    if (t != EditorTool.furniture) _pendingModel = null;
    _mergeFrom = null;
  });

  // ---------------- 一键建房间 / 面积标注 ----------------

  Widget get _areaChip => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ActionChip(
      avatar: Icon(
        Icons.square_foot,
        size: 14,
        color: _showAreas ? JiajiaColors.accent : JiajiaColors.text2,
      ),
      label: const Text('面积', style: TextStyle(fontSize: 13)),
      backgroundColor: _showAreas
          ? JiajiaColors.accentSoft
          : JiajiaColors.raised,
      side: BorderSide(
        color: _showAreas ? JiajiaColors.accent : JiajiaColors.line,
      ),
      labelStyle: TextStyle(
        color: _showAreas ? JiajiaColors.accent : JiajiaColors.text1,
        fontSize: 13,
      ),
      onPressed: () => setState(() => _showAreas = !_showAreas),
    ),
  );

  /// 房间环缓存：户型没变（墙数量+总长一致）时不重算 DFS。
  List<RoomLoop> _roomsOf(FloorPlan p) {
    double sig = 0;
    for (final w in p.walls.values) {
      sig = sig * 31 + w.length;
    }
    final key = '${p.walls.length}:$sig';
    if (key != _roomsSig) {
      _roomsSig = key;
      _rooms = p.roomLoops();
    }
    return _rooms;
  }

  /// 一键建房间：弹尺寸面板 → 在视口中央生成 4 面墙围合矩形（+门）→ 相机 fit。
  void _openRoomDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JiajiaColors.surface,
      builder: (_) => _RoomDialog(cam: _cam, canvasSize: _canvasSize),
    );
  }

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
                          child: Text(
                            '素材模型 · ${models.length} 件',
                            style: const TextStyle(
                              color: JiajiaColors.text1,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '原 app 内置',
                          style: TextStyle(
                            color: JiajiaColors.text2,
                            fontSize: 11,
                          ),
                        ),
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
                        for (var i = 0; i < ModelAssets.categories.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                ModelAssets.categories[i],
                                style: const TextStyle(fontSize: 12),
                              ),
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
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                          ),
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
                                  Icon(
                                    Icons.category,
                                    color: Color(0xFF000000 | m.color),
                                    size: 26,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m.label,
                                    style: const TextStyle(
                                      color: JiajiaColors.text1,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${m.w.toStringAsFixed(2)}×'
                                    '${m.d.toStringAsFixed(2)}×'
                                    '${m.h.toStringAsFixed(2)}m',
                                    style: TextStyle(
                                      color: JiajiaColors.text2,
                                      fontSize: 9,
                                    ),
                                  ),
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
      Offset(_canvasSize.width / 2, _canvasSize.height / 2),
    );
    final plan = ref.read(editorDocProvider).plan;
    final pos = _snapPoint(center, plan);
    ref.read(editorDocProvider.notifier).mutate((p) {
      final id = p.newId('i');
      p.items[id] = FurnitureItem(
        id: id,
        kind: FurnitureKind.asset,
        pos: pos,
        modelId: mid,
      );
      _sel = _Sel(id, 'item');
    });
    _toast('已放 ${asset.label}：2D 为占地框，切 3D 看真实形状');
  }

  // ---------------- 模型（原 app「模型」模块：门/窗/柱/楼梯/台面五金） ----------------

  /// 模型面板：5 类 tab + 图标网格（原 app draw/ 图标）。选中 → 进入放置模式。
  void _openModelItemsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: JiajiaColors.surface,
      builder: (ctx) {
        int catIdx = 0;
        return StatefulBuilder(
          builder: (ctx2, setIt) {
            final cat = ModelItems.categories[catIdx];
            final items = ModelItems.ofCategory(cat);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (BuildContext c, ScrollController sc) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '模型 · $cat（${items.length} 件）',
                            style: const TextStyle(
                              color: JiajiaColors.text1,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          '原 app 同款图标',
                          style: TextStyle(color: JiajiaColors.text2, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (var i = 0; i < ModelItems.categories.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(
                                ModelItems.categories[i],
                                style: const TextStyle(fontSize: 12),
                              ),
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
                            crossAxisCount: 3,
                            mainAxisSpacing: 8,
                          ),
                      itemCount: items.length,
                      itemBuilder: (_, j) {
                        final m = items[j];
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            _startPlacingModel(m);
                            Navigator.pop(ctx2);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              color: JiajiaColors.raised,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: JiajiaColors.line),
                            ),
                            child: Column(
                              children: [
                                Image.asset(
                                  m.icon,
                                  width: 34,
                                  height: 34,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Icon(
                                    m.place == ModelPlace.wall
                                        ? Icons.open_in_full
                                        : Icons.category,
                                    color: JiajiaColors.text2,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  m.label,
                                  style: const TextStyle(
                                    color: JiajiaColors.text1,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  m.specText,
                                  style: TextStyle(
                                    color: JiajiaColors.text2,
                                    fontSize: 9,
                                  ),
                                ),
                              ],
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

  /// 进入放置模式：门/窗 → 点墙开洞；柱/楼梯/台面五金 → 点地面摆放。
  void _startPlacingModel(ModelSpec m) {
    _setTool(EditorTool.furniture);
    _pendingModel = m;
    _toast(m.place == ModelPlace.wall
        ? '放置「${m.label}」：点一面墙开洞（可连续放，点「选择」结束）'
        : '放置「${m.label}」：点画布摆放（可连续放，点「选择」结束）');
  }

  void _placeModelItem(Offset local, FloorPlan plan) {
    final m = _pendingModel;
    if (m == null) return;
    final notifier = ref.read(editorDocProvider.notifier);
    final world = _cam.toWorld(local);
    if (m.place == ModelPlace.wall) {
      final hit = _hitWall(plan, world);
      if (hit == null) {
        _toast('点不到墙：门窗要贴着墙放，先点一面墙');
        return;
      }
      final wall = plan.walls[hit.id]!;
      // 点处投影到墙（offset = 距墙起点 a 的距离）
      final dv = world - wall.a;
      final ab = wall.b - wall.a;
      final alen = ab.length;
      final t = alen == 0 ? 0.0 : (dv.dx * ab.dx + dv.dy * ab.dy) / alen;
      final wM = m.defaultWmm / 1000;
      final off = (t.clamp(0.0, wall.length) - wM / 2).clamp(0.02, wall.length - wM / 2);
      final oid = plan.newId('o');
      notifier.mutate((p) {
        p.openings[oid] = Opening(
          id: oid,
          wallId: hit.id,
          kind: m.kind,
          doorType: m.kind == OpeningKind.door ? m.doorType : DoorType.single,
          offset: m.noLeaf ? t.clamp(0.0, wall.length) : off,
          width: wM,
          sill: m.sillMm / 1000,
          height: m.heightMm / 1000,
        );
      });
      _toast('${m.noLeaf ? '开洞' : '已开'} ${m.specText}');
    } else {
      final fid = plan.newId('i');
      notifier.mutate((p) {
        p.items[fid] = FurnitureItem(
          id: fid,
          kind: m.floorKind ?? FurnitureKind.asset,
          pos: _snapPoint(world, plan),
        );
        _sel = _Sel(fid, 'item');
      });
      _toast('已放「${m.label}」（选「选择」后可拖动位置）');
    }
  }

  /// 画布（CustomPaint）相对全局的左上角。
  /// 坑④（Flutter 3.47.9 实测）：同一 detector 里不同识别器坐标空间不一致——
  ///  · scale 识别器（onScale*）的 focalPoint 是【全局（窗口）坐标】，
  ///    直接当画布坐标用 toWorld，会把墙整体平移一个画布全局偏移
  ///    （= AppBar 高 + 安全区 ≈ 0.6m，用户反馈"墙起点比手指偏下"的根因）→ 需 _toLocal 转换；
  ///  · tap 识别器（onTapUp/onDoubleTapDown）的 localPosition 是【detector 局部坐标】
  ///    （与画布局部一致，= 全局 - _canvasOrigin()）→ 直接用，不转换；
  ///  · Listener（画布子树）的 localPosition 也是画布局部坐标。
  Offset _canvasOrigin() {
    final r = _paintKey.currentContext?.findRenderObject() as RenderBox?;
    final t = r?.getTransformTo(null);
    if (t == null) return Offset.zero;
    final v = t.getTranslation();
    return Offset(v.x, v.y);
  }

  /// 识别器坐标（全局）→ 画布局部坐标。
  Offset _toLocal(Offset recognizerCoord) => recognizerCoord - _canvasOrigin();

  // ---------------- 新建 / 保存 ----------------

  void _newPlan(FloorPlan plan) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: JiajiaColors.surface,
        title: const Text('新建户型', style: TextStyle(color: JiajiaColors.text1)),
        content: const Text(
          '清空当前画布？（可撤销）',
          style: TextStyle(color: JiajiaColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
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
            child: const Text(
              '新建',
              style: TextStyle(color: JiajiaColors.accent),
            ),
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

  /// 画墙吸附（原 app 式）：
  ///  ① 端点磁吸：靠近任意已有墙的端点（屏幕 ~14px 内）→ 精确吸附到该端点，墙与墙自动衔接；
  ///  ② 45° 角锁定：方向接近 0/45/90°/135°/…（±5° 内）→ 锁到精确角度，房间四壁更直；
  ///  ③ 兜底 0.05m 细网格（原 0.1m 会把起点拉离手指，改细网格降低偏移）。
  Vec2 _snapPoint(Vec2 w, FloorPlan plan, {Vec2? anchor}) {
    final r = math.max(0.2, 14 / _cam.ppm);
    Vec2? best;
    double bd = r;
    for (final wall in plan.walls.values) {
      for (final e in [wall.a, wall.b]) {
        final d = w.distanceTo(e);
        if (d < bd) {
          bd = d;
          best = e;
        }
      }
    }
    if (best != null) return best;
    if (anchor != null) {
      final dv = w - anchor;
      if (dv.length > 0.15) {
        final ang = math.atan2(dv.dy, dv.dx);
        final step = math.pi / 4;
        final near = (ang / step).round() * step;
        if ((ang - near).abs() < 0.09) {
          final dist = dv.length;
          w = anchor + Vec2(math.cos(near), math.sin(near)) * dist;
        }
      }
    }
    final g = 0.05;
    return Vec2((w.dx / g).round() * g, (w.dy / g).round() * g);
  }

  void _panStart(Offset local, FloorPlan plan) {
    // 画墙起点用「手指按下」位置（_downLocal），而非 scale 接受后的位置——
    // scale 识别器有 touchSlop（~18px），起点会跟着首段位移漂移（"墙起点偏下"的根因）
    final downLocal = _downLocal ?? local;
    final world = _cam.toWorld(downLocal);
    switch (_tool) {
      case EditorTool.wall:
        _wallStart = _snapPoint(world, plan);
        _wallCur = _wallStart;
        setState(() {});
      case EditorTool.select:
        final hit = _hitTest(plan, world);
        _draggingItem = hit != null && hit.id == _sel?.id && hit.type == 'item';
        break;
      default:
        break;
    }
  }

  /// 单指移动（scale 识别器的 1 指分支）：local=当前指位，delta=指位移。
  void _panUpdateAt(Offset local, Offset delta, FloorPlan plan) {
    switch (_tool) {
      case EditorTool.wall:
        _wallCur = _snapPoint(_cam.toWorld(local), plan, anchor: _wallStart);
        setState(() {});
      case EditorTool.select:
        if (_draggingItem && _sel != null) {
          ref.read(editorDocProvider.notifier).mutate((p2) {
            final item = p2.items[_sel!.id];
            if (item == null) return;
            item.pos =
                item.pos + Vec2(delta.dx / _cam.ppm, delta.dy / _cam.ppm);
          }, record: false);
        } else {
          _cam.panBy(delta);
          setState(() {});
        }
      default:
        _cam.panBy(delta);
        setState(() {});
    }
  }

  void _panEnd(FloorPlan plan) {
    _downLocal = null;
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
    _downLocal = null;
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
        final hit = _hitTest(plan, world);
        if (hit != null) {
          _mergeFrom = null;
          setState(() => _sel = hit);
        } else {
          // 点空处 → 选房间（原 app 分房/合并入口）
          final rooms = _roomsOf(plan);
          var idx = -1;
          for (var i = 0; i < rooms.length; i++) {
            if (plan.roomContains(rooms[i], world)) {
              idx = i;
              break;
            }
          }
          if (idx < 0) {
            setState(() => _sel = null);
            _mergeFrom = null;
          } else {
            final rooms2 = _roomsOf(plan);
            if (_mergeFrom != null && _mergeFrom! < rooms2.length) {
              _tryMerge(rooms2[_mergeFrom!], rooms2[idx]);
              _mergeFrom = null;
              setState(() => _sel = null);
            } else {
              setState(() => _sel = _Sel('room:$idx', 'room'));
            }
          }
        }
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
        if (_pendingModel != null) {
          _placeModelItem(local, plan);
        } else {
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
        }
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
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------------- 房间操作：拆 / 合 / 删（原 app「分房/合并」） ----------------

  int? _roomIndexOf() {
    if (_sel?.type != 'room') return null;
    final n = int.tryParse(_sel!.id.replaceFirst('room:', ''));
    return n;
  }

  /// 点「合并」后：记录来源房间，等用户点相邻房间。
  void _armMerge(int idx) {
    _mergeFrom = idx;
    _toast('点一个与它相邻的房间 → 合并（删共用隔墙）');
    setState(() {});
  }

  void _tryMerge(RoomLoop a, RoomLoop b) {
    final plan = ref.read(editorDocProvider).plan;
    final shared = plan.sharedWallBetween(a, b);
    if (shared == null) {
      _toast('两个房间不相邻（没有共用隔墙），不能合并');
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: JiajiaColors.surface,
        title: const Text('合并房间', style: TextStyle(color: JiajiaColors.text1)),
        content: const Text(
          '合并将删除两房间之间的隔墙（含该墙上的门窗开洞）？',
          style: TextStyle(color: JiajiaColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(editorDocProvider.notifier).mutate((p) {
                p.mergeRooms(a, b);
              });
              _sel = null;
              _mergeFrom = null;
              Navigator.pop(c);
              messenger?.showSnackBar(
                const SnackBar(content: Text('已合并：隔墙已删除')),
              );
            },
            child: const Text('合并', style: TextStyle(color: JiajiaColors.accent)),
          ),
        ],
      ),
    );
  }

  /// 拆房面板（DSS 同款，坑⑤）：方向（竖/横）+ 位置比例 + 是否加门。
  void _openSplitDialog(int roomIdx) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JiajiaColors.surface,
      builder: (_) => _SplitDialog(roomIdx: roomIdx),
    );
  }

  /// 删除房间：删不共用的墙（外墙保留）。
  void _removeRoom(int roomIdx) {
    final plan = ref.read(editorDocProvider).plan;
    final rooms = plan.roomLoops();
    if (roomIdx >= rooms.length) {
      _toast('房间已变化，请重新点选');
      _sel = null;
      return;
    }
    final loop = rooms[roomIdx];
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: JiajiaColors.surface,
        title: const Text('删除房间', style: TextStyle(color: JiajiaColors.text1)),
        content: Text(
          '删除该房间的隔墙（与其他房间/外部共用的外墙会保留）？',
          style: const TextStyle(color: JiajiaColors.text2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              var n = 0;
              ref.read(editorDocProvider.notifier).mutate((p) {
                n = p.removeRoomWalls(loop);
              });
              _sel = null;
              Navigator.pop(c);
              messenger?.showSnackBar(SnackBar(
                content: Text(n > 0 ? '已删除 $n 面隔墙' : '该房间全为共用墙，未删除'),
              ));
            },
            child: const Text('删除', style: TextStyle(color: JiajiaColors.accent)),
          ),
        ],
      ),
    );
  }

  /// 墙的完整编辑面板：尺寸 mm（长/墙高/墙厚）+ 开洞（门型/离墙距离/宽/高）。
  void _openWallDialog(String wallId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: JiajiaColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
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
    final opens = plan.openings.values.where((o) => o.wallId == wallId).length;
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
                    fontSize: 11,
                    color: JiajiaColors.text2,
                  ),
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

/// 选中房间的操作条（原 app 分房/合并入口）：面积 + 拆房/合并/删除。
class _RoomActionBar extends ConsumerWidget {
  final int roomIdx;
  final VoidCallback onSplit;
  final VoidCallback onMerge;
  final VoidCallback onRemove;
  final VoidCallback onClear;
  const _RoomActionBar({
    required this.roomIdx,
    required this.onSplit,
    required this.onMerge,
    required this.onRemove,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.read(editorDocProvider).plan;
    final loop = ref.read(editorDocProvider).plan.roomLoops()[
        roomIdx < _roomsCount(ref, plan) ? roomIdx : 0];
    final m2 = (loop.area * 100).roundToDouble() / 100;
    return Container(
      color: JiajiaColors.raised,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '房间 · ${m2.toStringAsFixed(1)}㎡（${loop.walls.length} 面墙）',
                  style: const TextStyle(
                    fontSize: 11,
                    color: JiajiaColors.text2,
                  ),
                ),
              ),
              _act('拆房', Icons.call_split, onSplit),
              _act('合并', Icons.merge, onMerge),
              _act('删除', Icons.delete_outline, onRemove),
              _act('取消', Icons.close, onClear),
            ],
          ),
        ),
      ),
    );
  }

  int _roomsCount(WidgetRef ref, FloorPlan p) => p.roomLoops().length;

  Widget _act(String label, IconData icon, VoidCallback cb) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: TextButton.icon(
          icon: Icon(icon, size: 15),
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onPressed: cb,
        ),
      );
}

/// 拆房面板：方向（竖/横）+ 位置比例（10~90%）+ 是否加门。
/// 坑⑤：BottomSheet 内容用 DraggableScrollableSheet（与墙面板同款）。
class _SplitDialog extends ConsumerStatefulWidget {
  final int roomIdx;
  const _SplitDialog({required this.roomIdx});

  @override
  ConsumerState<_SplitDialog> createState() => _SplitDialogState();
}

class _SplitDialogState extends ConsumerState<_SplitDialog> {
  String _axis = 'v'; // v=竖直隔墙（分左右） h=水平隔墙（分上下）
  double _frac = 0.5;
  bool _withDoor = true;

  @override
  Widget build(BuildContext context) {
    final plan = ref.read(editorDocProvider).plan;
    final idx = widget.roomIdx;
    final loop = idx < plan.roomLoops().length
        ? plan.roomLoops()[idx]
        : null;
    final messenger = ScaffoldMessenger.maybeOf(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.4,
      maxChildSize: 0.8,
      builder: (BuildContext c, ScrollController sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '拆房（房间 ${m2Text(loop)}）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: JiajiaColors.text1,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          if (loop == null)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '房间已变化，请重新点选',
                style: TextStyle(color: JiajiaColors.text2),
              ),
            )
          else ...[
            Row(
              children: [
                _axisChip('左右分（竖直墙）', 'v', _axis, () => setState(() => _axis = 'v')),
                const SizedBox(width: 8),
                _axisChip('上下分（水平墙）', 'h', _axis, () => setState(() => _axis = 'h')),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  '位置 ${( _frac * 100).round() }%',
                  style: const TextStyle(color: JiajiaColors.text2, fontSize: 12),
                ),
                Expanded(
                  child: Slider(
                    value: _frac,
                    min: 0.1,
                    max: 0.9,
                    divisions: 8,
                    onChanged: (v) => setState(() => _frac = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Checkbox(
                  value: _withDoor,
                  onChanged: (v) => setState(() => _withDoor = v ?? true),
                ),
                const Text('隔墙加门（900）', style: TextStyle(fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  var ok = false;
                  ref.read(editorDocProvider.notifier).mutate((p) {
                    ok = p.splitRoom(
                            loop,
                            axis: _axis,
                            frac: _frac,
                            withDoor: _withDoor) !=
                        null;
                  });
                  Navigator.pop(context);
                  messenger?.showSnackBar(SnackBar(
                    content: Text(
                      ok
                          ? '已拆房：隔墙 + ${_withDoor ? '门' : ''}'
                          : '该房间太小或非轴对齐，拆不了',
                    ),
                  ));
                },
                icon: const Icon(Icons.call_split, size: 18),
                label: const Text('拆分'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? m2Text(RoomLoop? l) => l == null ? '' : '${(l.area * 100).roundToDouble() / 100}㎡';

  Widget _axisChip(String label, String val, String cur, VoidCallback cb) {
    final on = cur == val;
    return ActionChip(
      label: Text(label, style: TextStyle(fontSize: 12, color: on ? JiajiaColors.accent : JiajiaColors.text1)),
      backgroundColor: on ? JiajiaColors.accentSoft : JiajiaColors.raised,
      side: BorderSide(color: on ? JiajiaColors.accent : JiajiaColors.line),
      onPressed: cb,
    );
  }
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
    final wall = ref.read(editorDocProvider).plan.walls[widget.wallId];
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
    for (final c in [_lenC, _hC, _tC, _offC, _wC, _ohC, _sillC]) {
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
      return const Padding(padding: EdgeInsets.all(24), child: Text('墙已不存在'));
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
            horizontal: 10,
            vertical: 10,
          ),
          border: const OutlineInputBorder(),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: BorderSide(color: JiajiaColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            borderSide: const BorderSide(color: JiajiaColors.accent),
          ),
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
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '墙尺寸',
            style: const TextStyle(
              color: JiajiaColors.text2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Expanded(child: mmField('尺寸', _lenC)),
              Expanded(child: mmField('墙高', _hC)),
              Expanded(child: mmField('墙厚', _tC)),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _accentBtn('应用墙尺寸（固定起点缩放）', _applyWallDims),
          ),
          const Divider(height: 24),
          Text(
            '开洞（门 / 窗）',
            style: const TextStyle(
              color: JiajiaColors.text2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final dt in DoorType.values)
                ChoiceChip(
                  label: Text(dt.label, style: const TextStyle(fontSize: 12)),
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
            children: [
              Expanded(child: mmField('离墙距离', _offC)),
              Expanded(child: mmField('宽', _wC)),
              Expanded(child: mmField(_asWindow ? '窗高' : '门高', _ohC)),
            ],
          ),
          if (_asWindow)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [Expanded(child: mmField('窗台高', _sillC))]),
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
                child: const Text(
                  '删除此墙',
                  style: TextStyle(color: Colors.redAccent),
                ),
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
    child: Text(
      label,
      style: const TextStyle(fontSize: 13, color: JiajiaColors.accent),
    ),
  );
}

// ---------------- 绘制 ----------------

class _PlanPainter extends CustomPainter {
  final FloorPlan plan;
  final CameraCtrl cam;
  final _Sel? sel;
  final (Vec2, Vec2)? draft; // 画墙拖拽中：(起点, 实时终点)
  final List<RoomLoop> rooms; // 房间环（面积标注 + 选中高亮）
  final bool showAreas;

  _PlanPainter({
    required this.plan,
    required this.cam,
    required this.sel,
    this.draft,
    this.rooms = const [],
    this.showAreas = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawColor(JiajiaColors.bgBase, BlendMode.src);
    _paintGrid(canvas, size);
    if (rooms.isNotEmpty && showAreas) _paintRooms(canvas);
    _paintWalls(canvas);
    _paintItems(canvas);
    _paintSelection(canvas);
    if (sel?.type == 'room') _paintSelRoom(canvas);
    if (draft != null) _paintWallDraft(canvas, draft!.$1, draft!.$2);
  }

  /// 选中房间：外轮廓高亮（accent 描边 + 半透明填充）。
  void _paintSelRoom(Canvas canvas) {
    final i = int.tryParse(sel!.id.replaceFirst('room:', ''));
    if (i == null || i >= rooms.length) return;
    final nodes = plan.orderedNodes(rooms[i]);
    if (nodes.length < 3) return;
    final path = Path();
    path.moveTo(cam.toScreen(nodes.first).dx, cam.toScreen(nodes.first).dy);
    for (final n in nodes.skip(1)) {
      final p = cam.toScreen(n);
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = JiajiaColors.accent.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = JiajiaColors.accent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  /// 房间面积标注（原 app「房间面积」同款）：房间中心画 面积㎡。
  void _paintRooms(Canvas canvas) {
    for (final r in rooms) {
      final p = cam.toScreen(r.centroid);
      final m2 = (r.area * 100).roundToDouble() / 100;
      final tp = TextPainter(
        text: TextSpan(
          text: '${m2.toStringAsFixed(1)}㎡',
          style: const TextStyle(
            color: JiajiaColors.accent,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final off = Offset(p.dx - tp.width / 2, p.dy - tp.height / 2);
      _paintLabelBg(canvas, off, tp);
      tp.paint(canvas, off);
    }
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
            style: const TextStyle(color: JiajiaColors.text3, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
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
            style: const TextStyle(color: JiajiaColors.text3, fontSize: 9),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
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
                : JiajiaColors.wall,
        );
        // 尺寸标注（mm）
        final mid = (p0o + p0i + p1o + p1i) / 4;
        final tp = TextPainter(
          text: TextSpan(
            text: '${toMm(w.length)}mm',
            style: TextStyle(
              color: sel?.id == w.id ? JiajiaColors.accent : JiajiaColors.text2,
              fontSize: 10,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelPos = mid - Offset(0, half + 14); // 墙外侧（上侧）
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
        Rect.fromLTRB(
          p.dx - 3,
          p.dy - 2,
          p.dx + tp.width + 3,
          p.dy + tp.height + 2,
        ),
        const Radius.circular(4),
      ),
      paint,
    );
  }

  void _paintOpenings(Canvas canvas, Wall w, Offset p0, Offset p1) {
    final opens = plan.openings.values.where((o) => o.wallId == w.id).toList();
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
              _dashed(
                canvas,
                hA,
                hB,
                paint,
                dash: 8,
                gap: 5,
                color: JiajiaColors.opening,
              );
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
    Canvas canvas,
    Offset hinge,
    Offset u,
    Offset n,
    double _,
    double radius, {
    double side = 1,
  }) {
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
      a0,
      a1 - a0,
      false,
      paint..strokeWidth = 1,
    );
  }

  void _dashed(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint p, {
    required double dash,
    required double gap,
    required Color color,
  }) {
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
          height: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintLabelBg(canvas, p, tp);
    tp.paint(canvas, p);
  }

  /// 返回墙的分段：(t0, t1, isSolid)。开洞处 isSolid=false。
  List<(double, double, bool)> _wallSegments(Wall w) {
    final opens =
        plan.openings.values
            .where((o) => o.wallId == w.id)
            .map(
              (o) => (
                (o.offset / w.length).clamp(0.0, 1.0),
                ((o.offset + o.width) / w.length).clamp(0.0, 1.0),
              ),
            )
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
        const Radius.circular(4),
      );
      canvas.drawRRect(rRect, Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawRRect(
        rRect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.5 : 1.5,
      );
      final label = i.modelId == null
          ? FurnitureCatalog.labelOf(i.kind)
          : (ModelAssets.byId(i.modelId!)?.label ??
                FurnitureCatalog.labelOf(i.kind));
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(color: JiajiaColors.text1, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
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
        e,
        6,
        Paint()
          ..color = JiajiaColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
    final mid = (p0 + p1) / 2;
    final tp = TextPainter(
      text: TextSpan(
        text: '${toMm(a.distanceTo(b))}mm',
        style: const TextStyle(color: JiajiaColors.accent, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _paintLabelBg(canvas, mid - Offset(tp.width / 2, -20), tp);
    tp.paint(canvas, mid - Offset(tp.width / 2, -20));
  }

  @override
  bool shouldRepaint(_PlanPainter old) => true;
}

// ---------------- 一键建房间面板（原 app「分房」式：输尺寸自动成房） ----------------

/// 输入 长×宽×高（mm）→ 在视口中央生成围合矩形房间（4 面墙，可选门）。
class _RoomDialog extends ConsumerStatefulWidget {
  final CameraCtrl cam;
  final Size canvasSize;
  const _RoomDialog({required this.cam, required this.canvasSize});

  @override
  ConsumerState<_RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends ConsumerState<_RoomDialog> {
  final _lC = TextEditingController(text: '4000');
  final _wC = TextEditingController(text: '3000');
  final _hC = TextEditingController(text: '2800');
  final _dwC = TextEditingController(text: '900');
  bool _withDoor = true;
  String? _err;

  @override
  void dispose() {
    for (final c in [_lC, _wC, _hC, _dwC]) {
      c.dispose();
    }
    super.dispose();
  }

  /// 常用房型一键预填（长×宽 mm）。
  void _preset(String l, String w) => setState(() {
    _lC.text = l;
    _wC.text = w;
    _err = null;
  });

  Widget _presetChip(String label, String l, String w) => ActionChip(
    avatar: const Icon(Icons.room, size: 14),
    label: Text(label),
    backgroundColor: JiajiaColors.raised,
    side: BorderSide(color: JiajiaColors.line),
    labelStyle: const TextStyle(color: JiajiaColors.text1, fontSize: 12),
    onPressed: () => _preset(l, w),
  );

  int? _parseMm(TextEditingController f, int min) {
    final v = int.tryParse(f.text.trim());
    return (v == null || v < min) ? null : v;
  }

  void _create() {
    final lMm = _parseMm(_lC, 500);
    final wMm = _parseMm(_wC, 500);
    final hMm = _parseMm(_hC, 1000);
    final dwMm = _parseMm(_dwC, 400);
    if (lMm == null ||
        wMm == null ||
        hMm == null ||
        (_withDoor && dwMm == null)) {
      setState(() => _err = '长/宽 ≥500mm，高 ≥1000mm，门宽 ≥400mm（单位 mm，整数）');
      return;
    }
    final l = fromMm(lMm), w = fromMm(wMm), h = fromMm(hMm);
    final center = widget.cam.toWorld(
      Offset(widget.canvasSize.width / 2, widget.canvasSize.height / 2),
    );
    final at = Vec2(center.dx - l / 2, center.dy - w / 2);
    ref.read(editorDocProvider.notifier).mutate((p) {
      p.addRoom(
        at: at,
        l: l,
        w: w,
        h: h,
        withDoor: _withDoor,
        doorW: _withDoor ? fromMm(dwMm!) : 0,
      );
    });
    HapticFeedback.mediumImpact();
    final after = ref.read(editorDocProvider).plan;
    widget.cam.fit(widget.canvasSize, after);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final note = '已建房间 $lMm×$wMm mm${_withDoor ? '（含门）' : ''}，相机已适配';
    Navigator.pop(context);
    messenger?.showSnackBar(SnackBar(content: Text(note)));
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
          horizontal: 10,
          vertical: 10,
        ),
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: JiajiaColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: const BorderSide(color: JiajiaColors.accent),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // 坑⑤（实测 3.47.9）：BottomSheet 内容自适应高度（Column/SCV 直接当 sheet
    // 子节点）时几何错乱——内容整块顶到屏幕下沿之外（按钮 y=924 点不到）。
    // 与 _WallDialog 同款：DraggableScrollableSheet 相对高度（0.5~0.85 屏）
    // + ListView 滚动，几何确定、键盘/小屏都稳。
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (BuildContext c, ScrollController sc) => ListView(
        controller: sc,
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '一键建房间',
                  style: const TextStyle(
                    color: JiajiaColors.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.close, size: 20),
              ),
            ],
          ),
          // 常用房型一键预填
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _presetChip('卧室 3000×4000', '3000', '4000'),
              _presetChip('客厅 4500×6000', '4500', '6000'),
              _presetChip('卫生间 2500×3000', '2500', '3000'),
              _presetChip('厨房 2400×2100', '2400', '2100'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '尺寸（mm，房间生成在视口中央）',
            style: const TextStyle(
              color: JiajiaColors.text2,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            children: [
              Expanded(child: mmField('长', _lC)),
              Expanded(child: mmField('宽', _wC)),
              Expanded(child: mmField('高', _hC)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Checkbox(
                value: _withDoor,
                onChanged: (v) => setState(() => _withDoor = v ?? false),
              ),
              const Text('底墙加门'),
              if (_withDoor) Expanded(child: mmField('门宽', _dwC)),
            ],
          ),
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _err!,
                style: const TextStyle(color: Color(0xFFE57373), fontSize: 12),
              ),
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.room, size: 18),
              label: const Text('创建房间', style: TextStyle(fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}
