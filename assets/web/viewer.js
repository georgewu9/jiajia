/* jiajia 3D 场景：户型 → 三维。单位：米。
 * 数据契约（Dart FloorPlan.toJsonString()）:
 * { name, walls:[{id,ax,ay,bx,by,t,h}], openings:[{id,wall,kind,off,w,sill}],
 *   items:[{id,kind,x,y,rot,model?,lib?,sw?,sd?,sh?,el?,off?}],
 *   libs:[{id,n,obj,w,d,h,c}] }   // libs 只含本户型 kind=lib 引用到的库模型
 * 桥：window.dart.postMessage(JSON.stringify({type,...}))
 *     Dart 调 window.jiajia.setPlan(jsonStr[, lang]) / .setMode('top'|'orbit'|'first')
 *          / .setLang('zh'|'en')
 */
(function () {
  'use strict';

  // ---------- v0.1.50 双语字符串表（3D 覆盖层文案）----------
  // 与 Dart 侧 lib/app/i18n.dart 同一套约定：key 小写 snake，缺词回退 zh。
  // 只翻用户看得见的覆盖层文案（提示条 / 滑杆名 / 方向键 aria / 占位盒名字）；
  // 数据键（kind / cat / plan.name / 库模型自定义名）保持中文，不做翻译。
  var STRINGS = {
    zh: {
      "hint_wait": '等待户型数据…',
      "hint_first": '方向键移动 · 拖动转向',
      "hint_top": '俯视图 · 双指缩放/平移',
      "hint_orbit": '轨道视角 · 拖动旋转',
      "fov": '广角',
      "eye": '人眼视角',
      "dp_up": '前进',
      "dp_left": '左移',
      "dp_right": '右移',
      "dp_down": '后退',
      "lib_default": '库模型',
      "model_missing": '模型缺失'
    },
    en: {
      "hint_wait": 'Waiting for floor plan…',
      "hint_first": 'D-pad to move · drag to look',
      "hint_top": 'Top view · pinch to zoom/pan',
      "hint_orbit": 'Orbit view · drag to rotate',
      "fov": 'Field of view',
      "eye": 'Eye height',
      "dp_up": 'Forward',
      "dp_left": 'Left',
      "dp_right": 'Right',
      "dp_down": 'Back',
      "lib_default": 'Model',
      "model_missing": 'Model missing'
    }
  };
  var lang = 'zh';

  /// 按当前语言取词；缺词回退 zh，再缺返回 key。
  function t(key) {
    var s = STRINGS[lang] && STRINGS[lang][key];
    if (!s) s = STRINGS.zh[key];
    return s || key;
  }

  /// models.js 条目的显示名：zh 用 n，en 优先 n_en（缺则回退中文名）。
  function modelName(m) {
    if (!m) return '';
    if (lang === 'en' && m.n_en) return String(m.n_en);
    return String(m.n || '');
  }

  /// 提示条：还没收到户型 → 等待文案；否则按当前视角取词。
  function updateHint() {
    var h = document.getElementById('hint');
    if (!h) return;
    if (!lastPlan) { h.textContent = t('hint_wait'); return; }
    h.textContent = mode === 'first' ? t('hint_first')
        : mode === 'top' ? t('hint_top') : t('hint_orbit');
  }

  /// 语言落地：<html lang>、滑杆名、方向键 aria-label、提示条。
  function applyLang() {
    document.documentElement.lang = lang === 'en' ? 'en' : 'zh-CN';
    var fovLab = document.getElementById('fovLab');
    var eyeLab = document.getElementById('eyeLab');
    if (fovLab) fovLab.textContent = t('fov');
    if (eyeLab) eyeLab.textContent = t('eye');
    var aria = [['dp-up', 'dp_up'], ['dp-left', 'dp_left'],
                ['dp-right', 'dp_right'], ['dp-down', 'dp_down']];
    for (var i = 0; i < aria.length; i++) {
      var b = document.getElementById(aria[i][0]);
      if (b) b.setAttribute('aria-label', t(aria[i][1]));
    }
    updateHint();
  }

  /// Dart → JS 语言切换；标签/图例（canvas 名字贴图）随语言重建。
  function setLang(l) {
    var want = l === 'en' ? 'en' : 'zh';
    if (want === lang) { applyLang(); return lang; }
    lang = want;
    applyLang();
    if (lastPlan) applyPlan(JSON.stringify(lastPlan));
    return lang;
  }

  // 与 Dart FurnitureCatalog 对齐（footprint w×d 米，3D 盒高，颜色）
  var CATALOG = {
    sofa: [1.8, 0.85, 0.8, 0x8fd3a8],
    bed: [1.6, 2.0, 0.5, 0x9fb6d9],
    table: [1.2, 0.8, 0.75, 0xd9b28a],
    chair: [0.45, 0.45, 0.9, 0xc7a88f],
    wardrobe: [1.2, 0.6, 2.1, 0xb08968],
    tv: [1.4, 0.4, 0.5, 0x6fcf97],
    plant: [0.4, 0.4, 1.2, 0x66bb6a],
    desk: [1.2, 0.6, 0.75, 0xc9a86a],
    stool: [0.35, 0.35, 0.45, 0xb98d6e],
    fridge: [0.7, 0.7, 1.8, 0xb8c4cc],
    washer: [0.6, 0.6, 0.9, 0xa8b8c4],
    heater: [0.5, 0.4, 0.8, 0xcc9a6e],
    stove: [0.75, 0.6, 0.85, 0x9aa4ab],
    hood: [0.9, 0.7, 1.6, 0x7d8a94],
    sink: [0.6, 0.5, 0.85, 0x8fa8b8],
    microwave: [0.5, 0.4, 0.35, 0x6e7a84],
    oven: [0.6, 0.6, 0.8, 0x8a97a1],
    coffee: [1.1, 0.6, 0.4, 0xa8896a],
    shoe: [0.8, 0.35, 1.0, 0x8f6f52],
    shelf: [0.8, 0.3, 1.8, 0x9c7a5a],
    // 原 app「模型」模块（柱/楼梯/台面/五金），与 Dart FurnitureCatalog 对齐
    pillar: [0.4, 0.4, 2.8, 0xb8b2a6],
    roundPillar: [0.4, 0.4, 2.8, 0xd8d4ca],
    stair: [1.2, 2.6, 2.8, 0x8b93a5],
    stairL: [1.2, 2.6, 2.8, 0x7d8a94],
    stairR: [1.2, 2.6, 2.8, 0x99a5b5],
    vanity: [0.9, 0.45, 0.8, 0xa8896a],
    gasStove: [0.75, 0.65, 0.85, 0x9aa4ab],
    gasCupboard: [0.6, 0.65, 1.9, 0x9c7a5a],
    drain: [0.15, 0.15, 0.05, 0x7d8a94],
    pipe: [0.1, 0.3, 2.8, 0x7d8a94],
    meterBox: [0.4, 0.12, 0.6, 0x8a97a1],
    waterMeter: [0.3, 0.25, 0.4, 0x8fa8b8],
    radiator: [1.2, 0.12, 0.8, 0xcc9a6e],
    acSlot: [0.7, 0.7, 0.1, 0x6e7a84],
    socketWall: [0.1, 0.1, 0.1, 0x6fcf97],
    socketFloor: [0.12, 0.12, 0.02, 0x6fcf97],
    switchPanel: [0.1, 0.1, 0.1, 0xe5c97a],
    landing: [1.2, 1.2, 0.15, 0x9aa4b8],
    arcWall: [2.0, 0.24, 2.8, 0x9c8b7a],
    // 梁柱菜单构件（v0.1.26：梁/风管/包管道/裸管/地台），亮色建筑风占位色
    beam: [2.4, 0.30, 0.35, 0xcfcfcf],
    duct: [1.2, 0.40, 0.35, 0xd8d8d8],
    pipeCase: [0.35, 0.35, 2.8, 0xe3e3e3],
    barePipe: [0.15, 0.15, 2.8, 0xbfc6ce],
    platform: [1.5, 1.2, 0.15, 0xe8e8e8],
    // 外部模型库（kind=lib）：尺寸取 item.sw/sd/sh，缺库/缺尺寸时兜底占位盒
    lib: [1.0, 0.6, 1.0, 0x8f8f8f],
  };

  // v0.1.26 亮色建筑风配色（设计稿「图2」）：天蓝背景 + 白地 + 淡灰墙 + 深灰线条。
  // 只作用于 3D 视图层，app 端 Flutter 暗色主题不受影响。
  var COL = {
    sky: 0x88c9f2,       // 场景背景（天蓝）
    floor: 0xffffff,     // 地面（纯白）
    wall: 0xcfcfcf,      // 墙体（淡灰）
    edge: 0x1a1a1a,      // 墙体轮廓 / 墙顶线（深灰近黑）
    railing: 0x2b2b2b,   // 栏杆（深灰）
    frame: 0x333333,     // 门窗框 / 门扇（深灰）
    glass: 0x99cde6      // 窗玻璃（半透明淡蓝）
  };

  var scene = new THREE.Scene();
  scene.background = new THREE.Color(COL.sky);
  scene.fog = new THREE.Fog(0xd8eefb, 45, 110); // 远景雾与天蓝背景同色系

  var camera = new THREE.PerspectiveCamera(
      55, 1, 0.05, 200);
  var renderer = new THREE.WebGLRenderer({
      canvas: document.getElementById('c'),
      antialias: true
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // 灯光（亮色配色下略提环境光，避免白墙/白地面死黑阴影）
  scene.add(new THREE.AmbientLight(0xffffff, 0.72));
  var sun = new THREE.DirectionalLight(0xfff6e8, 0.85);
  sun.position.set(8, 14, 6);
  scene.add(sun);

  var root = new THREE.Group(); // 户型整体
  scene.add(root);
  var wallAABB = []; // 第一视角碰撞：{ax,ay,bx,by,r}

  var controls = null;
  var mode = 'orbit';
  var fpYaw = 0, fpPitch = -0.05; // 第一视角
  var fpPos = new THREE.Vector3(0, 1.6, 0);
  var fpFov = 75;   // 第一视角「广角」当前值（度）：相机 fov
  var fpEye = 1.6;  // 第一视角「人眼视角」当前值（米）：玩家相机高度
  var miniT = 0;    // 小地图重画节流计时（10fps 足够，省绘图层）
  var moveVec = { x: 0, z: 0 }; // 摇杆
  var keys = {};
  var lastPlan = null;
  var doorsDbg = [], windowsDbg = []; // 调试：门窗实体引用
  var extOpeningsDbg = []; // v0.1.34：洞口外部 CC0 门窗实模（Group，debugExtOpenings 用）
  // v0.1.35：墙面切片登记（每段墙盒 Group）。调试探针 debugWallSlices/debugWallProbe 用；
  // 只是登记引用，不改渲染。
  var wallSlicesDbg = [];

  function post(msg) {
    if (window.dart && window.dart.postMessage) {
      window.dart.postMessage(JSON.stringify(msg));
    }
  }

  function clearRoot() {
    while (root.children.length) {
      var c = root.children.pop();
      root.remove(c);
    }
    wallAABB = [];
  }

  // 2D 平面坐标 (x, y) → 3D (x, y up?, z)
  function w2v(x, y) { return new THREE.Vector3(x, 0, y); }

  function buildFloor(bounds) {
    var w = bounds.maxX - bounds.minX + 2;
    var d = bounds.maxY - bounds.minY + 2;
    var cx = (bounds.minX + bounds.maxX) / 2;
    var cz = (bounds.minY + bounds.maxY) / 2;
    var floor = new THREE.Mesh(
        new THREE.BoxGeometry(w, 0.05, d),
        new THREE.MeshStandardMaterial({ color: COL.floor, roughness: 0.95 }));
    floor.position.set(cx, -0.025, cz);
    root.add(floor);

    // 网格线在纯白地面上用浅灰（深色网格会显得脏）
    var grid = new THREE.GridHelper(40, 80, 0xd0d0d0, 0xe6e6e6);
    grid.position.y = 0.001;
    root.add(grid);
  }

  // 墙体盒子 + 深色轮廓线（设计稿的墙顶线/墙边线效果）。
  // 返回 group（mesh + LineSegments），调用方设 position/rotation。
  function wallBox(len, h, t, color) {
    var geo = new THREE.BoxGeometry(len, h, t);
    var mesh = new THREE.Mesh(
        geo, new THREE.MeshStandardMaterial({ color: color, roughness: 0.9 }));
    var edges = new THREE.LineSegments(
        new THREE.EdgesGeometry(geo),
        new THREE.LineBasicMaterial({ color: COL.edge, transparent: true,
          opacity: 0.9 }));
    var g = new THREE.Group();
    g.add(mesh);
    g.add(edges);
    return g;
  }

  // 门窗框（v0.1.26 亮色建筑风）：深灰 #333 竖框 + 上下横框。
  // 局部坐标：X 沿墙、Y 竖直、Z 过墙厚；调用方设 position/rotation。
  function frameGroup(len, y0, h, th, color) {
    var g = new THREE.Group();
    var d = th + 0.02, w = 0.06;
    var mat = new THREE.MeshStandardMaterial({ color: color, roughness: 0.6 });
    var hh2 = Math.max(0.12, h);
    [-len / 2 + w / 2, len / 2 - w / 2].forEach(function (x) {
      var b = new THREE.Mesh(new THREE.BoxGeometry(w, hh2, d), mat);
      b.position.set(x, y0 + hh2 / 2, 0);
      g.add(b);
    });
    [y0 + w / 2, y0 + hh2 - w / 2].forEach(function (y) {
      var b = new THREE.Mesh(new THREE.BoxGeometry(len, w, d), mat);
      b.position.set(0, y, 0);
      g.add(b);
    });
    return g;
  }

  function wallSegments(wall, plan) {
    // 与 Dart 侧一致：开洞分段 [(t0,t1,solid)]
    // v0.1.18 修复：墙 JSON 只有 ax/ay/bx/by/t/h，没有 length 键——
    // 旧代码 wall.length||1 把米数当比例，开洞全画到墙外错位（3D 门窗消失/位置乱）
    var wdx = wall.bx - wall.ax, wdy = wall.by - wall.ay;
    var wlen = Math.sqrt(wdx * wdx + wdy * wdy) || 1;
    var opens = plan.openings
        .filter(function (o) { return o.wall === wall.id; })
        .map(function (o) {
          return [o.off / wlen, (o.off + o.w) / wlen, o];
        })
        .sort(function (a, b) { return a[0] - b[0]; });
    var out = [];
    var cur = 0;
    opens.forEach(function (o) {
      if (o[0] > cur) out.push([cur, o[0], 'solid']);
      out.push([o[0], o[1], o[2]]); // 开洞段，带 opening 对象
      cur = o[1];
    });
    if (cur < 1) out.push([cur, 1, 'solid']);
    if (!out.length) out.push([0, 1, 'solid']);
    return out;
  }

  // v0.1.35：墙盒统一入口——登记到 wallSlicesDbg 再挂 root（渲染不变）。
  // role: 'solid' 整段墙 / 'below' 窗台下实墙 / 'lintel' 过梁段（洞口顶→墙顶）。
  function addWallSlice(g, role) {
    g.userData = g.userData || {};
    g.userData.wallSlice = role;
    wallSlicesDbg.push(g);
    root.add(g);
    return g;
  }

  function buildWalls(plan) {
    plan.walls.forEach(function (w) {
      var ax = w.ax, ay = w.ay, bx = w.bx, by = w.by;
      var dx = bx - ax, dy = by - ay;
      var len = Math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) return;
      var ang = Math.atan2(dy, dx); // 平面角 → 3D 绕 Y 轴 = -ang? 平面 y→z
      var th = w.t || 0.24;
      var hh = w.h || 2.8;

      wallSegments(w, plan).forEach(function (seg) {
        var t0 = seg[0], t1 = seg[1], kind = seg[2];
        var segLen = len * (t1 - t0);
        if (segLen < 1e-4) return;
        var mx = ax + dx * ((t0 + t1) / 2);
        var my = ay + dy * ((t0 + t1) / 2);

        // v0.1.39 第一视角碰撞：按开洞分段登记碰撞线段。
        // 旧实现把整条墙线推进 wallAABB（不看 openings）→ 门洞在 3D 里是空的，
        // 碰撞层仍是实心墙，第一视角走到门洞被「隐形墙」挡住。
        // solid 段 / window 段都挡人（窗台下实墙 + 过梁在竖向封死整面墙，
        // 人不能穿窗，水平上按实墙算）；door 门洞不登记——门扇/实模门一律
        // 不加碰撞（用户拍板：门洞可通行）。
        if (kind === 'solid' || kind.kind === 'window') {
          wallAABB.push({
            ax: ax + dx * t0, ay: ay + dy * t0,
            bx: ax + dx * t1, by: ay + dy * t1,
            r: th / 2 + 0.35
          });
        }

        if (kind === 'solid') {
          var box = wallBox(segLen, hh, th, COL.wall);
          box.position.copy(w2v(mx, my));
          box.position.y = hh / 2;
          box.rotation.y = -ang;
          addWallSlice(box, 'solid');
        } else if (kind.kind === 'door') {
          // 门洞：上方过梁 + 门扇
          // v0.1.35：过梁起点改用「洞口顶」。挂实模时 = 洞高（ht，如 2.06/2.14），
          // 否则旧实现固定 2.1 起 → 实模门顶到 2.1 之间会漏一条缝且过梁高度算错。
          // 未挂实模：仍沿用 2.1m 起 + 墙高 >2.15 才画的旧行为（回归不变）。
          var extM = kind.m ? extSource(kind.m) : null;
          var extG = extM ? extGeometry(kind.m) : null;
          var dTop = extG
              ? Math.min(hh, (kind.sill || 0) + (kind.ht || 2.1))
              : 2.1;
          if (hh - dTop > 0.005) {
            var lintel = wallBox(segLen, hh - dTop, th, COL.wall);
            lintel.position.copy(w2v(mx, my));
            lintel.position.y = dTop + (hh - dTop) / 2;
            lintel.rotation.y = -ang;
            addWallSlice(lintel, 'lintel');
          }
          // v0.1.18 门扇：单开整宽、双开两端各半宽；铰链在开洞端部，
          // 90° 张开——内开朝法向内侧（side=1）、外开朝外侧（side=-1）
          // v0.1.34：洞口挂了外部 CC0 门窗模型（Opening.m）→ 用 OBJ 实模替换通用门扇。
          // 未挂模型 / 模型表缺失（旧包）→ 保持原通用门扇逻辑不变。
          if (extG) {
            root.add(openingModel(kind.m, extM, extG, segLen,
                Math.min(kind.ht || 2.05, hh - (kind.sill || 0)),
                kind.sill || 0, mx, my, ang));
          } else if (kind.dt === 'single' || kind.dt === 'double') {
            // 门框（深灰 #333）：门洞两侧 + 门头
            var dFrame = frameGroup(segLen, 0, Math.min(2.1, hh), th, COL.frame);
            dFrame.position.copy(w2v(mx, my));
            dFrame.rotation.y = -ang;
            root.add(dFrame);
            var L = len;
            var n2x = -dy / L, n2z = dx / L; // 法向（墙方向左侧）
            var side = kind.out ? -1 : 1;
            var lW = kind.dt === 'double' ? segLen / 2 : segLen;
            var leafH = 2.05;
            var leafAngle = -Math.atan2(n2z, n2x);
            var leafMat = new THREE.MeshStandardMaterial({
              color: COL.frame, roughness: 0.6
            });
            var addLeaf = function (hx, hy, wl) {
              var leaf = new THREE.Mesh(
                  new THREE.BoxGeometry(wl, leafH, 0.04), leafMat);
              leaf.rotation.y = leafAngle;
              leaf.position.copy(w2v(
                  hx + n2x * side * (th / 2 + wl / 2),
                  hy + n2z * side * (th / 2 + wl / 2)));
              leaf.position.y = leafH / 2;
              root.add(leaf);
              doorsDbg.push(leaf);
            };
            var p0x = ax + dx * t0, p0y = ay + dy * t0;
            var p1x = ax + dx * t1, p1y = ay + dy * t1;
            // v0.1.24：单开按铰链侧（hl=false → 右开，铰链在开洞右端）
            if (kind.dt === 'double') {
              addLeaf(p0x, p0y, lW);
              addLeaf(p1x, p1y, lW);
            } else if (kind.hl === false) {
              addLeaf(p1x, p1y, lW);
            } else {
              addLeaf(p0x, p0y, lW);
            }
          }
        } else if (kind.kind === 'window') {
          // 窗：墙面切片三段齐全（台下 / 过梁 / 两侧 solid 段）+ 洞内几何（通用玻璃 或 实模）
          // v0.1.35 修复（用户截图「3D 墙上部缺口」）：旧实现玻璃高度用 hh-sill 一路撑到墙顶，
          // 挂实模时实模只占 sill..sill+ht（如 0.9..2.2）→ 洞口顶到墙顶的过梁段整段没画，
          // 墙上出现一个方形缺口。现在统一按洞口矩形（sill → sill+ht）算洞内几何，
          // 洞口顶以上一律补过梁切片；挂 m 只是把洞内玻璃换成 OBJ 实模。
          var sill = (kind.sill == null) ? 0.9 : kind.sill;
          var wExt = kind.m ? extSource(kind.m) : null;
          var wG = wExt ? extGeometry(kind.m) : null;
          var opTop = Math.min(hh, sill + (kind.ht || (hh - sill)));
          var rectH = Math.max(0, opTop - sill);
          // 台下实墙（sill>0 才画，窗台高 0 时不该有矮墙）
          if (sill > 0.005) {
            var below = wallBox(segLen, sill, th, COL.wall);
            below.position.copy(w2v(mx, my));
            below.position.y = sill / 2;
            below.rotation.y = -ang;
            addWallSlice(below, 'below');
          }
          // 过梁段（洞口顶 → 墙顶）
          if (hh - opTop > 0.005) {
            var lintel = wallBox(segLen, hh - opTop, th, COL.wall);
            lintel.position.copy(w2v(mx, my));
            lintel.position.y = opTop + (hh - opTop) / 2;
            lintel.rotation.y = -ang;
            addWallSlice(lintel, 'lintel');
          }
          if (wG) {
            root.add(openingModel(kind.m, wExt, wG, segLen, rectH, sill, mx, my, ang));
          } else {
            // 未挂实模：通用窗框 + 玻璃（尺寸=洞口矩形；旧实现是撑到墙顶，见上）
            var glassH = Math.max(0.05, rectH);
            // 窗框（深灰 #333）：窗洞四周
            var wFrame = frameGroup(segLen, sill, glassH, th, COL.frame);
            wFrame.position.copy(w2v(mx, my));
            wFrame.rotation.y = -ang;
            root.add(wFrame);
            var glass = new THREE.Mesh(
                new THREE.BoxGeometry(segLen, glassH, 0.04),
                new THREE.MeshStandardMaterial({
                  color: COL.glass, transparent: true, opacity: 0.45,
                  side: THREE.DoubleSide
                }));
            glass.position.copy(w2v(mx, my));
            glass.position.y = sill + glassH / 2;
            glass.rotation.y = -ang;
            root.add(glass);
            windowsDbg.push(glass);
          }
        }
      });
    });
  }

  // ---------- 素材模型（原 app OBJ/MTL，内嵌于 models.js） ----------
  // 解析 OBJ 文本 → 按 usemtl 分组的面板；归一化：模型 y 轴竖直，
  // scale = 目标高 / 模型高，落地面、x/z 居中。
  function parseOBJ(txt) {
    var verts = [], groups = {}, cur = 'default', mats = [];
    var lines = txt.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (line.charAt(0) === 'v' && line.charAt(1) === ' ') {
        var p = line.trim().split(/\s+/);
        verts.push([+p[1], +p[2], +p[3]]);
      } else if (line.indexOf('usemtl') === 0) {
        cur = line.trim().split(/\s+/)[1] || 'default';
      } else if (line.charAt(0) === 'f') {
        if (mats.indexOf(cur) < 0) mats.push(cur);
        var t = line.trim().split(/\s+/), idx = [];
        for (var k = 1; k < t.length; k++) idx.push(+t[k].split('/')[0]);
        if (idx.length < 3) continue;
        if (!groups[cur]) groups[cur] = [];
        var g = groups[cur];
        for (var j = 1; j < idx.length - 1; j++) {
          g.push(idx[0], idx[j], idx[j + 1]);
        }
      }
    }
    return { verts: verts, groups: groups, mats: mats };
  }

  // v0.1.32：mc 里的颜色既可能是 '#FFFFFF' 也可能是 '0xFFFFFF'（models.js 用 0x 前缀），
  // 统一解析；解析失败退回模型主色，避免 NaN 颜色导致整件模型渲染成黑色。
  function parseHexColor(v, fallback) {
    if (v == null) return fallback;
    if (typeof v === 'number') return isFinite(v) ? v : fallback;
    var s = String(v).trim().replace(/^#/, '').replace(/^0x/i, '');
    var n = parseInt(s, 16);
    return isFinite(n) ? n : fallback;
  }

  var modelCache = {};
  function modelGeometry(mid) {
    if (modelCache[mid]) return modelCache[mid];
    var model = window.JJ_MODELS && window.JJ_MODELS[mid];
    if (!model || !model.o) return null;
    var parsed = parseOBJ(model.o);
    var mc = model.mc || {};
    var meshes = [];
    for (var i = 0; i < parsed.mats.length; i++) {
      var matName = parsed.mats[i];
      var arr = parsed.groups[matName];
      if (!arr || arr.length < 3) continue;
      var geo = new THREE.BufferGeometry();
      var pos = new Float32Array(arr.length * 3);
      for (var a = 0; a < arr.length; a++) {
        var v = parsed.verts[arr[a] - 1];
        pos[a * 3] = v[0]; pos[a * 3 + 1] = v[1]; pos[a * 3 + 2] = v[2];
      }
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.computeVertexNormals();
      var col = parseHexColor(mc[matName], model.c);
      meshes.push(new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
        color: col, side: THREE.DoubleSide })));
    }
    if (!meshes.length) return null;
    var inner = new THREE.Group();
    meshes.forEach(function (m) { inner.add(m); });
    // 归一化：包围盒 y 轴 = 竖直；目标高 model.h；落地面、x/z 居中
    var bb = new THREE.Box3().setFromObject(inner);
    var size = bb.getSize(new THREE.Vector3());
    var s = size.y > 1e-6 ? model.h / size.y :
        model.h / Math.max(size.x, size.z);
    inner.scale.setScalar(s);
    inner.updateMatrixWorld(true);
    bb = new THREE.Box3().setFromObject(inner);
    var c = bb.getCenter(new THREE.Vector3());
    inner.position.x = -c.x;
    inner.position.z = -c.z;
    inner.position.y = -bb.min.y;
    var outer = new THREE.Group();
    outer.add(inner);
    modelCache[mid] = outer;
    return outer;
  }

  // ---------- 扩展素材（v0.1.34：用户提供的 7 个 CC0 门窗 OBJ，models_ext.js）----------
  // 与内置 JJ_MODELS 的区别：外部 OBJ 的源单位/缩放不可靠（如 frenchDoors bbox 只有
  // 0.11×0.01×0.10m，规格要求 1.14×0.14×1.00m）→ 按规格 w/d/h 三轴 fit（同 libGeometry），
  // 而不是内置素材那样只 fit 高度。window.JJ_EXT_MODELS 可能不存在（旧包升级 / 未打包）。
  var extCache = {};
  function extSource(mid) {
    // typeof 判空：旧包升级（未打包 models_ext.js）时不能抛 ReferenceError
    if (!mid || typeof window.JJ_EXT_MODELS === 'undefined' ||
        !window.JJ_EXT_MODELS) return null;
    return window.JJ_EXT_MODELS[mid] || null;
  }

  function extGeometry(mid) {
    if (extCache[mid]) return extCache[mid];
    var model = extSource(mid);
    if (!model || !model.o) return null;
    var parsed = parseOBJ(model.o);
    var meshes = [];
    for (var i = 0; i < parsed.mats.length; i++) {
      var matName = parsed.mats[i];
      var arr = parsed.groups[matName];
      if (!arr || arr.length < 3) continue;
      var geo = new THREE.BufferGeometry();
      var pos = new Float32Array(arr.length * 3);
      for (var a = 0; a < arr.length; a++) {
        var v = parsed.verts[arr[a] - 1];
        if (!v) continue;
        pos[a * 3] = v[0]; pos[a * 3 + 1] = v[1]; pos[a * 3 + 2] = v[2];
      }
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.computeVertexNormals();
      meshes.push(new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
        color: parseHexColor(model.c, 0x8f8f8f), side: THREE.DoubleSide })));
    }
    if (!meshes.length) return null;
    var inner = new THREE.Group();
    meshes.forEach(function (m) { inner.add(m); });
    var bb = new THREE.Box3().setFromObject(inner);
    var size = bb.getSize(new THREE.Vector3());
    var tw = model.w > 0 ? model.w : 1.0;
    var td = model.d > 0 ? model.d : 0.2;
    var th = model.h > 0 ? model.h : 2.0;
    inner.scale.set(size.x > 1e-6 ? tw / size.x : 1,
                    size.y > 1e-6 ? th / size.y : 1,
                    size.z > 1e-6 ? td / size.z : 1);
    inner.updateMatrixWorld(true);
    bb = new THREE.Box3().setFromObject(inner);
    var c = bb.getCenter(new THREE.Vector3());
    inner.position.x = -c.x;
    inner.position.z = -c.z;
    inner.position.y = -bb.min.y;
    var outer = new THREE.Group();
    outer.add(inner);
    extCache[mid] = outer;
    return outer;
  }

  // 洞口实模：把已按规格 w/d/h 归一化的 OBJ 组 fit 进洞口（宽/高），沿墙朝向摆放。
  // 只被挂在 Opening.m 上的门窗使用；通用门扇/窗玻璃路径不受影响。
  function openingModel(mid, model, proto, width, height, sill, cx, cy, ang) {
    var inst = proto.clone(true);
    var mw = model.w > 0 ? model.w : width;
    var mh = model.h > 0 ? model.h : height;
    inst.scale.set(width / mw, height / mh, 1);
    inst.position.copy(w2v(cx, cy));
    inst.position.y = sill || 0;
    inst.rotation.y = -ang;
    inst.userData = { opening: mid, model: mid, extModel: true };
    extOpeningsDbg.push({ id: mid, width: width, height: height, obj: inst });
    return inst;
  }

  // ---------- 模型库（外部 OBJ）：复用同一条 parseOBJ，三轴 fit 到目标 w/d/h ----------
  // 与内置 JJ_MODELS 的区别：库模型的目标尺寸来自 LibModel（用户可改），
  // 三个轴分别缩放（OBJ 单位可能是 mm/cm/inch，按目标盒强行归一）。
  var libCache = {};
  function findLib(libs, id) {
    if (!libs || !id) return null;
    for (var i = 0; i < libs.length; i++) {
      if (libs[i].id === id) return libs[i];
    }
    return null;
  }

  function libGeometry(lib) {
    var key = lib.id + '|' + lib.w + '|' + lib.d + '|' + lib.h;
    if (libCache[key]) return libCache[key];
    if (!lib.obj) return null;
    var parsed = parseOBJ(lib.obj);
    var color = (typeof lib.c === 'number') ? lib.c : 0x8f8f8f;
    var meshes = [];
    for (var i = 0; i < parsed.mats.length; i++) {
      var matName = parsed.mats[i];
      var arr = parsed.groups[matName];
      if (!arr || arr.length < 3) continue;
      var geo = new THREE.BufferGeometry();
      var pos = new Float32Array(arr.length * 3);
      for (var a = 0; a < arr.length; a++) {
        var v = parsed.verts[arr[a] - 1];
        if (!v) continue; // 越界索引 → 该顶点留 (0,0,0)，不抛
        pos[a * 3] = v[0]; pos[a * 3 + 1] = v[1]; pos[a * 3 + 2] = v[2];
      }
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      geo.computeVertexNormals();
      meshes.push(new THREE.Mesh(geo, new THREE.MeshStandardMaterial({
        color: color, side: THREE.DoubleSide })));
    }
    if (!meshes.length) return null;
    var inner = new THREE.Group();
    meshes.forEach(function (m) { inner.add(m); });
    var bb = new THREE.Box3().setFromObject(inner);
    var size = bb.getSize(new THREE.Vector3());
    var tw = lib.w > 0 ? lib.w : 1.0;
    var td = lib.d > 0 ? lib.d : 0.6;
    var th = lib.h > 0 ? lib.h : 1.0;
    inner.scale.set(size.x > 1e-6 ? tw / size.x : 1,
                    size.y > 1e-6 ? th / size.y : 1,
                    size.z > 1e-6 ? td / size.z : 1);
    inner.updateMatrixWorld(true);
    bb = new THREE.Box3().setFromObject(inner);
    var c = bb.getCenter(new THREE.Vector3());
    inner.position.x = -c.x;
    inner.position.z = -c.z;
    inner.position.y = -bb.min.y; // 落地面
    var outer = new THREE.Group();
    outer.add(inner);
    libCache[key] = outer;
    return outer;
  }

  // 缺库回退：占位盒上方用 canvas 纹理贴名字（不引入字体 loader）。
  function makeLabel(text) {
    var s = String(text || t('lib_default'));
    var cv = document.createElement('canvas');
    cv.width = 512; cv.height = 128;
    var g = cv.getContext('2d');
    g.clearRect(0, 0, cv.width, cv.height);
    g.font = 'bold 56px sans-serif';
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    var tw = g.measureText(s).width;
    g.fillStyle = 'rgba(255,255,255,0.85)';
    g.fillRect((cv.width - tw) / 2 - 12, 20, tw + 24, 88);
    g.fillStyle = '#333333';
    g.fillText(s, cv.width / 2, cv.height / 2);
    var tex = new THREE.CanvasTexture(cv);
    tex.needsUpdate = true;
    var sp = new THREE.Sprite(new THREE.SpriteMaterial({
      map: tex, transparent: true, depthWrite: false }));
    sp.scale.set(1.5, 0.375, 1);
    return sp;
  }

  // v0.1.22：程序化楼梯（stair/stairL/stairR 无 OBJ 模型时回退，不再是方盒子）
  // stepH=总高/步数，run1=直段步数，turn=转折（L 型有 90° 拐弯），run2=拐弯后步数
  function buildStairs(kind, w, d, h, color, x, y, rotDeg, elev) {
    var group = new THREE.Group();
    var mat = new THREE.MeshStandardMaterial({ color: color });
    var isL = (kind === 'stairL' || kind === 'stairR');
    var total = isL ? 8 : 10;
    var run1 = isL ? 4 : total;
    var run2 = isL ? total - run1 : 0;
    var stepH = h / total;
    var treadD = d / (run1 + 1); // 直段每级踏深
    var treadW = w;
    // 直段台阶
    for (var s = 0; s < run1; s++) {
      var tread = new THREE.Mesh(
          new THREE.BoxGeometry(treadW, stepH, treadD), mat);
      tread.position.set(0, stepH * (s + 0.5),
          -d / 2 + treadD * (s + 0.5));
      group.add(tread);
    }
    // L 型拐弯段：从直段末端 90° 转，横向铺台阶
    if (run2 > 0) {
      var baseY = stepH * run1;
      var turnDir = (kind === 'stairR') ? 1 : -1;
      var segW = w / (run2 + 1);
      for (var s2 = 0; s2 < run2; s2++) {
        var t2 = new THREE.Mesh(
            new THREE.BoxGeometry(segW, stepH, treadD), mat);
        t2.position.set(
            turnDir * (w / 2 - segW * (s2 + 0.5)),
            baseY + stepH * (s2 + 0.5),
            d / 2 - treadD / 2);
        group.add(t2);
      }
    }
    // v0.1.24：楼梯整体离地高度（i.el，米；二楼/错层）
    group.position.set(x, elev || 0, y);
    group.rotation.y = -((rotDeg || 0) * Math.PI / 180);
    return group;
  }

  // 圆柱/裸管：3D 用回转体（CylinderGeometry, 24 段）而非方盒子——
  // 与 2D 平面图上的圆形符号保持一致，靠墙包管不会看起来是方柱。
  function buildCylinder(w, d, h, color, x, y, rotDeg) {
    var r = Math.min(w, d) / 2;
    var cyl = new THREE.Mesh(
        new THREE.CylinderGeometry(r, r, h, 24),
        new THREE.MeshStandardMaterial({ color: color }));
    cyl.position.set(x, h / 2, y);
    cyl.rotation.y = -((rotDeg || 0) * Math.PI / 180);
    return cyl;
  }

  // ---------- v0.1.32：程序化家具（亮色建筑风盒子组合） ----------
  // 设计基准取 item 当前 w/d/h（米），子件按比例排布；建完统一按包围盒
  // fit 到 w/d/h（scale），保证双击改尺寸后整体等比缩放、底面落在 y=0。
  // 材质一律 clone 后涂色，不改共享/缓存材质（同栏杆先例）。
  var FURN_COL = {
    wood: 0xc9a86a,   // 浅木
    wood2: 0xa8896a,  // 深木
    white: 0xffffff,  // 床垫/家电白
    grey: 0xd8d8d8,   // 布面/灰
    metal: 0x8b93a5,  // 金属件
    dark: 0x333333,   // 门缝/细黑线
    glass: 0x99cde6,  // 玻璃门（半透明）
    linen: 0xdcdcdc   // 枕头/坐垫浅灰（白床垫上要能看出分层）
  };

  function buildProcedural(kind, w, d, h, mat) {
    var kinds = ['bed', 'sofa', 'table', 'coffee', 'desk', 'chair',
                 'stool', 'fridge', 'washer'];
    if (kinds.indexOf(kind) < 0) return null;
    var g = new THREE.Group();
    function pm(hex, opts) {
      var m = mat.clone();
      m.color.setHex(hex);
      if (opts) {
        if (opts.transparent != null) m.transparent = opts.transparent;
        if (opts.opacity != null) m.opacity = opts.opacity;
        if (opts.roughness != null) m.roughness = opts.roughness;
      }
      return m;
    }
    function box(bw, bh, bd, x, y, z, m) {
      var mesh = new THREE.Mesh(new THREE.BoxGeometry(bw, bh, bd), m);
      mesh.position.set(x, y, z);
      g.add(mesh);
      return mesh;
    }
    function cyl(r, hh, x, y, z, m, seg) {
      var mesh = new THREE.Mesh(
          new THREE.CylinderGeometry(r, r, hh, seg || 20), m);
      mesh.position.set(x, y, z);
      g.add(mesh);
      return mesh;
    }

    if (kind === 'bed') {
      // 床架 + 床垫（白）+ 2 枕头 + 床头板；床垫顶 ≈ 0.5h，床头板到 h
      box(w * 0.97, h * 0.18, d * 0.94, 0, h * 0.09, 0, pm(FURN_COL.wood2));
      box(w * 0.92, h * 0.32, d * 0.84, 0, h * 0.34, 0, pm(FURN_COL.white));
      box(w, h, d * 0.04, 0, h * 0.5, -d * 0.48, pm(FURN_COL.wood));
      var pw = w * 0.36, pd = d * 0.14, ph = h * 0.11;
      box(pw, ph, pd, -w * 0.21, h * 0.55, -d * 0.31, pm(FURN_COL.linen));
      box(pw, ph, pd, w * 0.21, h * 0.55, -d * 0.31, pm(FURN_COL.linen));
    } else if (kind === 'sofa') {
      // 坐垫 + 靠背 + 2 扶手 + 4 短脚（宽度自适应 0.7/1.0/1.3）
      var legH = h * 0.12, baseH = h * 0.25;
      var lx = w * 0.42, lz = d * 0.36;
      [[-lx, -lz], [lx, -lz], [-lx, lz], [lx, lz]].forEach(function (p) {
        box(w * 0.06, legH, d * 0.05, p[0], legH / 2, p[1], pm(FURN_COL.wood2));
      });
      box(w * 0.96, baseH, d * 0.92, 0, legH + baseH / 2, 0, pm(FURN_COL.grey));
      var seatTop = legH + baseH;
      box(w * 0.62, h * 0.14, d * 0.62, 0, seatTop + h * 0.07, d * 0.02,
          pm(FURN_COL.white));
      box(w * 0.96, h * 0.52, d * 0.16, 0, seatTop + h * 0.26, -d * 0.42,
          pm(FURN_COL.grey));
      box(w * 0.12, h * 0.50, d * 0.92, -w * 0.42, legH + h * 0.25, 0,
          pm(FURN_COL.grey));
      box(w * 0.12, h * 0.50, d * 0.92, w * 0.42, legH + h * 0.25, 0,
          pm(FURN_COL.grey));
    } else if (kind === 'table' || kind === 'coffee' || kind === 'desk') {
      // 桌面 + 4 腿；desk 加一块背侧挡板（示意）
      var topH = h * 0.08, legT = Math.max(0.03, w * 0.055);
      box(w, topH, d, 0, h - topH / 2, 0, pm(FURN_COL.wood));
      var legH2 = h - topH, ox = w * 0.5 - legT * 1.4,
          oz = d * 0.5 - legT * 1.4;
      [[-ox, -oz], [ox, -oz], [-ox, oz], [ox, oz]].forEach(function (p) {
        box(legT, legH2, legT, p[0], legH2 / 2, p[1], pm(FURN_COL.wood2));
      });
      if (kind === 'desk') {
        box(w * 0.78, h * 0.42, Math.max(0.02, d * 0.05),
            0, h * 0.52, -d * 0.30, pm(FURN_COL.wood2));
      }
    } else if (kind === 'chair') {
      // 座面 + 靠背 + 4 腿
      var chLeg = h * 0.45, chSeat = h * 0.08, ct = Math.max(0.025, w * 0.08);
      box(w * 0.95, chSeat, d * 0.95, 0, chLeg + chSeat / 2, 0,
          pm(FURN_COL.wood));
      box(w * 0.95, h * 0.45, d * 0.09, 0, chLeg + chSeat + h * 0.225,
          -d * 0.44, pm(FURN_COL.wood2));
      [[-1, -1], [1, -1], [-1, 1], [1, 1]].forEach(function (s) {
        box(ct, chLeg, ct, s[0] * (w * 0.42), chLeg / 2, s[1] * (d * 0.40),
            pm(FURN_COL.wood2));
      });
    } else if (kind === 'stool') {
      // 圆台面 + 4 条斜撑腿
      var r = Math.min(w, d) * 0.5, topT = h * 0.12, legs = h * 0.88;
      cyl(r, topT, 0, h - topT / 2, 0, pm(FURN_COL.wood), 24);
      for (var si = 0; si < 4; si++) {
        var ang = Math.PI / 4 + si * Math.PI / 2;
        var lx2 = Math.cos(ang) * r * 0.58, lz2 = Math.sin(ang) * r * 0.58;
        var leg = cyl(Math.max(0.015, r * 0.07), legs, lx2, legs / 2, lz2,
                      pm(FURN_COL.wood2), 10);
        leg.rotation.z = -Math.cos(ang) * 0.10;
        leg.rotation.x = Math.sin(ang) * 0.10;
      }
    } else if (kind === 'fridge') {
      // 高柜体（白）+ 2 条横向门缝 + 右侧竖拉手
      var fw = w * 0.96, fd = d * 0.92, fh = h * 0.99;
      box(fw, fh, fd, 0, fh / 2, 0, pm(FURN_COL.white));
      box(fw * 0.98, Math.max(0.012, h * 0.007), Math.max(0.012, d * 0.02),
          0, h * 0.62, fd / 2, pm(FURN_COL.dark));
      box(fw * 0.98, Math.max(0.012, h * 0.007), Math.max(0.012, d * 0.02),
          0, h * 0.30, fd / 2, pm(FURN_COL.dark));
      box(Math.max(0.025, w * 0.05), h * 0.18, Math.max(0.02, d * 0.04),
          fw / 2 - w * 0.06, h * 0.45, fd / 2 + d * 0.01,
          pm(FURN_COL.metal));
    } else if (kind === 'washer') {
      // 矮柜体（白）+ 圆形玻璃门 + 顶部控制面板条
      var ww = w * 0.96, wd = d * 0.92, wh = h * 0.96;
      box(ww, wh, wd, 0, wh / 2, 0, pm(FURN_COL.white));
      var dr = Math.min(w, d) * 0.30;
      var door = cyl(dr, Math.max(0.02, d * 0.04), 0, h * 0.45, wd / 2,
                     pm(FURN_COL.glass, { transparent: true, opacity: 0.55,
                                          roughness: 0.25 }), 28);
      door.rotation.x = Math.PI / 2;
      box(ww * 0.90, Math.max(0.05, h * 0.08), Math.max(0.02, d * 0.05),
          0, h * 0.86, wd / 2 - d * 0.01, pm(FURN_COL.grey));
    } else {
      return null;
    }

    // 整体 fit 到 w/d/h（等比 3 轴拉伸到目标盒），底面 y=0、xz 居中
    var bb = new THREE.Box3().setFromObject(g);
    var sz = bb.getSize(new THREE.Vector3());
    var outer = new THREE.Group();
    outer.add(g);
    g.scale.set(w / Math.max(sz.x, 1e-6), h / Math.max(sz.y, 1e-6),
                d / Math.max(sz.z, 1e-6));
    g.updateMatrixWorld(true);
    bb = new THREE.Box3().setFromObject(g);
    var c = bb.getCenter(new THREE.Vector3());
    g.position.set(-c.x, -bb.min.y, -c.z);
    return outer;
  }

  function buildItems(plan) {
    plan.items.forEach(function (i) {
      // v0.1.20：自定义尺寸（米）→ 目录盒/模型等比缩放
      // v0.1.37：实模离地高度（mm → 米）。awning 等吊装件挂在 off 高度上；
      // 与楼梯的 i.el（楼层/错层整体抬升）相加，不互相覆盖。
      var liftM = (typeof i.off === 'number' && isFinite(i.off)) ? i.off / 1000 : 0;
      var sw = (typeof i.sw === 'number') ? i.sw : null;
      var sd = (typeof i.sd === 'number') ? i.sd : null;
      var sh = (typeof i.sh === 'number') ? i.sh : null;
      // v0.1.34：素材模型查表扩展——内置 JJ_MODELS 优先，其次用户 CC0 门窗 JJ_EXT_MODELS。
      // JJ_EXT_MODELS 可能未定义（旧包升级 / 包内漏打）→ 占位盒 + 名字，绝不崩。
      var modelMid = null, mdef = null, mExt = false;
      if (i.model) {
        if (window.JJ_MODELS && window.JJ_MODELS[i.model]) {
          modelMid = i.model;
          mdef = window.JJ_MODELS[i.model];
        } else if (extSource(i.model)) {
          modelMid = i.model;
          mdef = extSource(i.model);
          mExt = true;
        } else {
          // 查到不到的 model id（旧包/models_ext.js 缺席）：占位盒 + 名字
          var mxw = sw != null ? sw : 0.9;
          var mxd = sd != null ? sd : 0.2;
          var mxh = sh != null ? sh : 2.1;
          var gmiss = new THREE.Group();
          var mbox = new THREE.Mesh(new THREE.BoxGeometry(mxw, mxh, mxd),
              new THREE.MeshStandardMaterial({
                color: 0x8f8f8f, transparent: true, opacity: 0.55 }));
          mbox.position.y = mxh / 2;
          gmiss.add(mbox);
          var mlbl = makeLabel(t('model_missing'));
          mlbl.position.set(0, mxh + 0.22, 0);
          gmiss.add(mlbl);
          gmiss.position.set(i.x, (i.el || 0) + liftM, i.y);
          gmiss.rotation.y = -((i.rot || 0) * Math.PI / 180);
          gmiss.userData = { id: i.id, kind: i.kind, model: i.model,
                             placeholder: true, labelItem: true };
          root.add(gmiss);
          return;
        }
      }
      if (modelMid) {
        var proto = mExt ? extGeometry(modelMid) : modelGeometry(modelMid);
        if (proto) {
          var mesh = proto.clone(true);
          var md = mdef;
          if (sw != null || sd != null || sh != null) {
            var sx = sw != null && md.w ? sw / md.w : 1;
            var sz = sd != null && md.d ? sd / md.d : 1;
            var sy = sh != null && md.h ? sh / md.h : (sx + sz) / 2;
            mesh.scale.set(sx, sy, sz);
          }
          // v0.1.37：底面按离地高度抬高（此前固定 0，连 i.el 也忽略了）
          mesh.position.set(i.x, (i.el || 0) + liftM, i.y);
          mesh.rotation.y = -((i.rot || 0) * Math.PI / 180);
          // 栏杆素材（原 app 分类「栏杆」）统一改深灰 #2B2B2B（设计稿配色）。
          // 材质按实例 clone，避免污染 modelCache 里共享的 proto 材质。
          if (md.cat === '栏杆') {
            mesh.traverse(function (o) {
              if (o.isMesh && o.material) {
                o.material = o.material.clone();
                o.material.color.setHex(COL.railing);
              }
            });
          }
          mesh.userData = { id: i.id, kind: i.kind, model: modelMid };
          root.add(mesh);
          return;
        }
      }
      var spec = CATALOG[i.kind];
      if (!spec) return;
      // 模型库（外部 OBJ）：i.kind === 'lib' 时按 i.lib 在 plan.libs 里查；
      // 查到 → 同一 parseOBJ 管线出 mesh（fit 到目标尺寸），查不到 → 占位盒+名字。
      if (i.kind === 'lib') {
        var lib = findLib(plan.libs, i.lib);
        if (lib) {
          var proto = libGeometry(lib);
          if (proto) {
            var inst = proto.clone(true);
            var sx = (sw != null && lib.w) ? sw / lib.w : 1;
            var sz = (sd != null && lib.d) ? sd / lib.d : 1;
            var sy = (sh != null && lib.h) ? sh / lib.h : (sx + sz) / 2;
            inst.scale.set(sx, sy, sz);
            inst.position.set(i.x, i.el || 0, i.y);
            inst.rotation.y = -((i.rot || 0) * Math.PI / 180);
            inst.userData = { id: i.id, kind: i.kind, lib: lib.id,
                              placeholder: false };
            root.add(inst);
            return;
          }
        }
        // 旧数据 / 未导入库：占位盒 + 名字（绝不崩），尺寸按 item/catalog 兜底
        var lbw = sw != null ? sw : (lib && lib.w > 0 ? lib.w : spec[0]);
        var lbd = sd != null ? sd : (lib && lib.d > 0 ? lib.d : spec[1]);
        var lbh = sh != null ? sh : (lib && lib.h > 0 ? lib.h : spec[2]);
        var lbc = (lib && typeof lib.c === 'number') ? lib.c : spec[3];
        var grp = new THREE.Group();
        var pbox = new THREE.Mesh(new THREE.BoxGeometry(lbw, lbh, lbd),
            new THREE.MeshStandardMaterial({
              color: lbc, transparent: true, opacity: 0.55 }));
        pbox.position.y = lbh / 2;
        grp.add(pbox);
        var lbl = makeLabel((lib && lib.n) || t('lib_default'));
        lbl.position.set(0, lbh + 0.22, 0);
        grp.add(lbl);
        grp.position.set(i.x, i.el || 0, i.y);
        grp.rotation.y = -((i.rot || 0) * Math.PI / 180);
        grp.userData = { id: i.id, kind: i.kind,
                         lib: lib ? lib.id : (i.lib || null),
                         placeholder: true, labelItem: true };
        root.add(grp);
        return;
      }
      var bw = sw != null ? sw : spec[0];
      var bd = sd != null ? sd : spec[1];
      var bh = sh != null ? sh : spec[2];
      // v0.1.22：楼梯类 kind → 程序化台阶（替代方盒子）
      if (i.kind === 'stair' || i.kind === 'stairL' || i.kind === 'stairR') {
        var stairs = buildStairs(i.kind, bw, bd, bh, spec[3],
            i.x, i.y, i.rot || 0, i.el);
        stairs.userData = { id: i.id, kind: i.kind };
        root.add(stairs);
        return;
      }
      // 圆柱/包管/裸管 → 圆柱体（回转体），不吃下面的方盒子分支
      if (i.kind === 'roundPillar' || i.kind === 'barePipe') {
        var cyl = buildCylinder(bw, bd, bh, spec[3], i.x, i.y, i.rot || 0);
        cyl.userData = { id: i.id, kind: i.kind };
        root.add(cyl);
        return;
      }
      // v0.1.32：核心家具 → 程序化几何（床/沙发/桌/椅/凳/冰箱/洗衣机），
      // 不再落到下面单盒分支；i.model / i.lib 已在上面优先处理。
      var proc = buildProcedural(i.kind, bw, bd, bh,
          new THREE.MeshStandardMaterial({ color: spec[3] }));
      if (proc) {
        proc.position.set(i.x, i.el || 0, i.y);
        proc.rotation.y = -((i.rot || 0) * Math.PI / 180);
        proc.userData = { id: i.id, kind: i.kind };
        root.add(proc);
        return;
      }
      var box = new THREE.Mesh(
          new THREE.BoxGeometry(bw, bh, bd),
          new THREE.MeshStandardMaterial({ color: spec[3] }));
      box.position.set(i.x, (i.el || 0) + liftM + bh / 2, i.y);
      box.rotation.y = -((i.rot || 0) * Math.PI / 180);
      box.userData = { id: i.id, kind: i.kind };
      root.add(box);
    });
  }

  function boundsOf(plan) {
    var b = { minX: 0, minY: 0, maxX: 4, maxY: 4 };
    plan.walls.forEach(function (w) {
      b.minX = Math.min(b.minX, w.ax, w.bx);
      b.maxX = Math.max(b.maxX, w.ax, w.bx);
      b.minY = Math.min(b.minY, w.ay, w.by);
      b.maxY = Math.max(b.maxY, w.ay, w.by);
    });
    return b;
  }

  function centerOf(plan) {
    var b = boundsOf(plan);
    return new THREE.Vector3(
        (b.minX + b.maxX) / 2, 0, (b.minY + b.maxY) / 2);
  }

  // ---------- 第一视角小地图（右上角 2D 户型 + 玩家朝向锥） ----------
  // 画布 240×240 物理像素、CSS 120px（2x，白底半透明由 #mini 的样式负责）。
  // 坐标：平面 (x,y) → 小地图像素 (x, y) 直接等比缩放，与 3D 的 w2v(x,y)=(x,0,y)
  // 一致（平面 y 轴 = 3D z 轴 = 画布向下），所以朝向只需换算相机视线的 xz 分量。
  var miniCv = document.getElementById('mini');
  var miniCtx = miniCv ? miniCv.getContext('2d') : null;

  function drawMini() {
    if (!miniCtx) return;
    var W = miniCv.width, H = miniCv.height; // 240×240
    var g = miniCtx;
    g.clearRect(0, 0, W, H);
    if (!lastPlan || !lastPlan.walls || !lastPlan.walls.length) return;

    // 1) 户型包围盒 → 等比 fit（四周留 14px 边距），居中
    var b = boundsOf(lastPlan);
    var pad = 14;
    var spanX = Math.max(0.5, b.maxX - b.minX);
    var spanY = Math.max(0.5, b.maxY - b.minY);
    var s = Math.min((W - pad * 2) / spanX, (H - pad * 2) / spanY);
    var ox = (W - spanX * s) / 2 - b.minX * s;
    var oy = (H - spanY * s) / 2 - b.minY * s;
    var mp = function (x, y) { return [x * s + ox, y * s + oy]; };

    // 2) 户型墙线：#333，3px（墙厚不画，保持雷达图清爽）
    g.strokeStyle = '#333';
    g.lineWidth = 3;
    g.lineCap = 'round';
    g.beginPath();
    for (var i = 0; i < lastPlan.walls.length; i++) {
      var w = lastPlan.walls[i];
      var p0 = mp(w.ax, w.ay), p1 = mp(w.bx, w.by);
      g.moveTo(p0[0], p0[1]);
      g.lineTo(p1[0], p1[1]);
    }
    g.stroke();

    // 3) 玩家：蓝色楔形（雷达锥）+ 中心实心圆点
    //    朝向取「相机实际视线」的水平分量：主循环里 camera.rotateY(fpYaw + π)，
    //    而 three.js 相机默认看向自身 -Z，所以视线 = (sin yaw, cos yaw)（xz 平面）。
    //    （注意：主循环里算出的 fx/fz = (-sin,-cos) 与视线正好相反，是既有代码的
    //     历史约定；锥体按“画面里看到的方向”画，才和人眼所见一致。）
    var pp = mp(fpPos.x, fpPos.z);
    var ang = Math.atan2(Math.cos(fpYaw), Math.sin(fpYaw));
    var R = 26, half = 0.40; // 锥长 26px、半张角约 23°
    g.beginPath();
    g.moveTo(pp[0], pp[1]);
    g.arc(pp[0], pp[1], R, ang - half, ang + half);
    g.closePath();
    g.fillStyle = 'rgba(59,130,246,.30)';
    g.fill();
    g.strokeStyle = 'rgba(59,130,246,.85)';
    g.lineWidth = 1.5;
    g.stroke();

    // 中心点：白描边保证压住墙线也看得清
    g.beginPath();
    g.arc(pp[0], pp[1], 5, 0, Math.PI * 2);
    g.fillStyle = '#3B82F6';
    g.fill();
    g.strokeStyle = '#fff';
    g.lineWidth = 2;
    g.stroke();
  }

  function applyPlan(jsonStr) {
    clearRoot();
    doorsDbg = []; windowsDbg = []; extOpeningsDbg = []; wallSlicesDbg = [];
    var plan = JSON.parse(jsonStr);
    lastPlan = plan;
    updateHint(); // 首次拿到户型 → 提示条从「等待」换成视角提示
    var b = boundsOf(plan);
    buildFloor(b);
    buildWalls(plan);
    buildItems(plan);

    var c = centerOf(plan);
    if (mode === 'top') {
      camera.position.set(c.x, 25, c.z);
      camera.up.set(0, 0, -1);
      camera.lookAt(c);
    } else if (mode === 'first') {
      fpPos.copy(c);
      fpPos.y = fpEye; // 人眼高度跟随滑杆（默认 1.6m）
      fpYaw = Math.PI; // 面向户型
      fpPitch = -0.05;
    } else {
      camera.position.set(c.x + 6, 7, c.z + 8);
      camera.up.set(0, 1, 0);
      camera.lookAt(c);
    }
    if (controls) controls.target.copy(c);
    post({ type: 'planLoaded', walls: plan.walls.length,
        items: plan.items.length });
  }

  window.jiajia = {
    // v0.1.50：setPlan(jsonStr[, lang]) —— 初始化就把语言带上，省一次往返；
    // 第二参非字符串（旧 Dart 调用只传一个参数）时忽略，保持兼容。
    setPlan: function (jsonStr, l) {
      if (typeof l === 'string') setLang(l);
      applyPlan(jsonStr);
    },
    // v0.1.50：语言变化时 Dart 再发一条 → 覆盖层文案/名字贴图重建。
    setLang: setLang,
    lang: function () { return lang; },
    // 调试探针：返回门窗实体的世界坐标（自动化验证用，无 UI 影响）
    debugOpenings: function () {
      return {
        doors: doorsDbg.map(function (d) {
          return { x: +d.position.x.toFixed(3), y: +d.position.y.toFixed(3),
            z: +d.position.z.toFixed(3), w: d.geometry.parameters.width };
        }),
        windows: windowsDbg.map(function (g) {
          return { x: +g.position.x.toFixed(3), y: +g.position.y.toFixed(3),
            z: +g.position.z.toFixed(3), w: g.geometry.parameters.width };
        }),
      };
    },
    // 调试探针：家具/库模型实体（自动化验证用；不改变 UI）
    debugItems: function () {
      var out = [];
      root.children.forEach(function (o) {
        if (!o.userData || !o.userData.id) return;
        var meshes = 0, verts = 0;
        o.traverse(function (c) {
          if (c.isMesh) {
            meshes++;
            if (c.geometry && c.geometry.attributes &&
                c.geometry.attributes.position) {
              verts += c.geometry.attributes.position.count;
            }
          }
        });
        var box = new THREE.Box3().setFromObject(o);
        var sz = box.getSize(new THREE.Vector3());
        out.push({ id: o.userData.id, kind: o.userData.kind,
          lib: o.userData.lib || null, meshes: meshes, verts: verts,
          placeholder: !!o.userData.placeholder,
          label: !!o.userData.labelItem,
          size: [+sz.x.toFixed(3), +sz.y.toFixed(3), +sz.z.toFixed(3)],
          // v0.1.37：底面世界坐标（离地高度断言用：awning 应 ≈1.5）
          min: [+box.min.x.toFixed(3), +box.min.y.toFixed(3),
                +box.min.z.toFixed(3)] });
      });
      return out;
    },
    // v0.1.34：洞口外部 CC0 门窗实模探针（尺寸/网格数，自动化验证用）
    debugExtOpenings: function () {
      return extOpeningsDbg.map(function (e) {
        var meshes = 0, verts = 0;
        e.obj.traverse(function (c) {
          if (c.isMesh) {
            meshes++;
            if (c.geometry && c.geometry.attributes &&
                c.geometry.attributes.position) {
              verts += c.geometry.attributes.position.count;
            }
          }
        });
        var box = new THREE.Box3().setFromObject(e.obj);
        var sz = box.getSize(new THREE.Vector3());
        return { id: e.id, width: e.width, height: e.height,
                 meshes: meshes, verts: verts,
                 size: [+sz.x.toFixed(3), +sz.y.toFixed(3), +sz.z.toFixed(3)] };
      });
    },
    // v0.1.35：墙面切片探针（世界 bbox + 角色）。验证开洞上方过梁/台下段是否成片。
    debugWallSlices: function () {
      return wallSlicesDbg.map(function (g) {
        var b = new THREE.Box3().setFromObject(g);
        return { role: (g.userData && g.userData.wallSlice) || '?',
          min: [+b.min.x.toFixed(3), +b.min.y.toFixed(3), +b.min.z.toFixed(3)],
          max: [+b.max.x.toFixed(3), +b.max.y.toFixed(3), +b.max.z.toFixed(3)] };
      });
    },
    // v0.1.35：采样点射线探针——从 (x,y,z) 沿 dir（默认 +z，反推 3m 起射）
    // 只打墙面切片的 mesh（不含 EdgesGeometry 线框：Line 的 raycast threshold
    // 默认 1m，会把相邻墙段的描边也算命中 → 误判成「洞上方有实墙」）。
    debugWallProbe: function (x, y, z, dir) {
      var d = dir || [0, 0, 1];
      var vec = new THREE.Vector3(d[0], d[1], d[2]).normalize();
      var origin = new THREE.Vector3(x, y, z)
          .sub(vec.clone().multiplyScalar(3));
      var rc = new THREE.Raycaster(origin, vec, 0, 6);
      rc.params.Line.threshold = 0;
      var meshes = [];
      wallSlicesDbg.forEach(function (g) {
        g.children.forEach(function (c) { if (c.isMesh) meshes.push(c); });
      });
      var hits = rc.intersectObjects(meshes, false);
      return { hit: hits.length > 0, count: hits.length,
        role: hits.length ? (hits[0].object.parent &&
          hits[0].object.parent.userData &&
          hits[0].object.parent.userData.wallSlice) || null : null,
        point: hits.length ? [+hits[0].point.x.toFixed(3),
          +hits[0].point.y.toFixed(3), +hits[0].point.z.toFixed(3)] : null };
    },
    // v0.1.34：OBJ 文本解析统计（复用 viewer 内 parseOBJ；验证面数/字符数不被截断）
    modelStats: function (mid) {
      var m = (window.JJ_MODELS && window.JJ_MODELS[mid]) ||
              (window.JJ_EXT_MODELS && window.JJ_EXT_MODELS[mid]);
      if (!m || !m.o) return null;
      var p = parseOBJ(m.o);
      var tris = 0;
      Object.keys(p.groups).forEach(function (k) {
        tris += Math.floor(p.groups[k].length / 3);
      });
      return { id: mid, name: modelName(m), chars: m.o.length, verts: p.verts.length,
               tris: tris, mats: p.mats.length };
    },
    setMode: function (m) {
      mode = m;
      var isFirst = m === 'first';
      // 第一视角专属 UI：小地图 / 滑杆卡片 / 方向键一起显隐；
      // 旧摇杆（#joy）不再参与第一视角——原 app 用 D-pad，摇杆只留代码不显示。
      document.getElementById('joy').style.display = 'none';
      document.getElementById('mini').style.display = isFirst ? 'block' : 'none';
      document.getElementById('fpanel').style.display = isFirst ? 'block' : 'none';
      document.getElementById('dpad').style.display = isFirst ? 'grid' : 'none';
      // v0.1.50：提示条文案走 STRINGS（随语言切换）
      updateHint();
      var c = lastPlan ? centerOf(lastPlan) : new THREE.Vector3(0, 0, 0);
      if (controls) {
        controls.enabled = m !== 'first';
      }
      if (lastPlan) applyPlan(JSON.stringify(lastPlan));
      // 进入第一视角套用滑杆当前值（广角/人眼高度）；离开时恢复默认 55° 透视，
      // 免得轨道/俯视视角被广角拉变形
      if (isFirst) {
        camera.fov = fpFov;
        camera.updateProjectionMatrix();
        fpPos.y = fpEye;
        drawMini();
      } else {
        camera.fov = 55;
        camera.updateProjectionMatrix();
      }
      moveVec.x = 0; moveVec.z = 0; // 切模式清掉残留方向，避免一直平移
      post({ type: 'mode', mode: m });
    },
    // 调试探针：第一视角 UI 状态（无 UI 影响，自动化验证用）
    uiState: function () {
      var vis = function (id) {
        var el = document.getElementById(id);
        return !!el && getComputedStyle(el).display !== 'none';
      };
      return {
        mode: mode, fov: fpFov, fovApplied: +camera.fov.toFixed(2),
        eye: fpEye, camY: +fpPos.y.toFixed(2),
        pos: [+fpPos.x.toFixed(3), +fpPos.z.toFixed(3)], yaw: +fpYaw.toFixed(3),
        mini: vis('mini'), panel: vis('fpanel'), dpad: vis('dpad'),
        joy: vis('joy'), move: [moveVec.x, moveVec.z]
      };
    },
    // v0.1.39 调试探针：把第一视角玩家放到 (x,z)、朝向 yaw（第一视角碰撞
    // 自动化验证用；不改任何渲染/交互逻辑，仅写 fpPos/fpYaw）
    debugPlace: function (x, z, yaw) {
      fpPos.x = x; fpPos.z = z; fpPos.y = fpEye;
      if (typeof yaw === 'number') fpYaw = yaw;
      camera.position.copy(fpPos);
      return [+fpPos.x.toFixed(3), +fpPos.z.toFixed(3), +fpYaw.toFixed(3)];
    },
    // v0.1.39 调试探针：第一视角碰撞线段表（验证门洞不登记、窗段与实墙登记）
    debugWallAABB: function () {
      return wallAABB.map(function (s) {
        return { ax: +s.ax.toFixed(3), ay: +s.ay.toFixed(3),
                 bx: +s.bx.toFixed(3), by: +s.by.toFixed(3),
                 r: +s.r.toFixed(3) };
      });
    }
  };

  // 第一视角碰撞：圆 vs 线段
  function collide(nx, nz) {
    for (var i = 0; i < wallAABB.length; i++) {
      var s = wallAABB[i];
      var abx = s.bx - s.ax, aby = s.by - s.ay;
      var len2 = abx * abx + aby * aby;
      if (len2 < 1e-6) continue;
      var t = ((nx - s.ax) * abx + (nz - s.ay) * aby) / len2;
      t = Math.max(0, Math.min(1, t));
      var px = s.ax + abx * t, py = s.ay + aby * t;
      var dx = nx - px, dy = nz - py;
      var d2 = dx * dx + dy * dy;
      if (d2 < s.r * s.r) {
        var d = Math.sqrt(d2) || 1e-6;
        nx = px + dx / d * s.r;
        nz = py + dy / d * s.r;
      }
    }
    return [nx, nz];
  }

  // 第一视角控制：拖动转向
  var drag = null;
  var cv = document.getElementById('c');
  cv.addEventListener('pointerdown', function (e) {
    if (mode === 'first') {
      drag = { x: e.clientX, y: e.clientY };
      cv.setPointerCapture(e.pointerId);
    }
  });
  cv.addEventListener('pointermove', function (e) {
    if (drag && mode === 'first') {
      fpYaw -= (e.clientX - drag.x) * 0.004;
      fpPitch -= (e.clientY - drag.y) * 0.004;
      fpPitch = Math.max(-1.2, Math.min(1.2, fpPitch));
      drag.x = e.clientX;
      drag.y = e.clientY;
    }
  });
  cv.addEventListener('pointerup', function () { drag = null; });

  // 虚拟摇杆
  var joy = document.getElementById('joy');
  var knob = document.getElementById('knob');
  var joyDrag = null;
  joy.addEventListener('pointerdown', function (e) {
    joyDrag = true;
    joy.setPointerCapture(e.pointerId);
    moveJoy(e);
  });
  joy.addEventListener('pointermove', function (e) {
    if (joyDrag) moveJoy(e);
  });
  joy.addEventListener('pointerup', function () {
    joyDrag = false;
    moveVec.x = 0; moveVec.z = 0;
    knob.style.transform = 'translate(0,0)';
  });
  function moveJoy(e) {
    var r = joy.getBoundingClientRect();
    var cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    var dx = (e.clientX - cx) / (r.width / 2);
    var dy = (e.clientY - cy) / (r.height / 2);
    var m = Math.sqrt(dx * dx + dy * dy);
    if (m > 1) { dx /= m; dy /= m; m = 1; }
    moveVec.x = dx;
    moveVec.z = dy;
    knob.style.transform = 'translate(' + dx * 28 + 'px,' + dy * 28 + 'px)';
  }

  // ---------- 第一视角滑杆：广角（相机 fov） / 人眼视角（相机高度） ----------
  var fovSl = document.getElementById('fovSl');
  var eyeSl = document.getElementById('eyeSl');
  var fovVal = document.getElementById('fovVal');
  var eyeVal = document.getElementById('eyeVal');

  function applyFov() {
    var v = parseFloat(fovSl.value);
    if (!isFinite(v)) v = 75;
    fpFov = Math.max(40, Math.min(110, v));
    fovVal.textContent = Math.round(fpFov) + '°'; // 仿原 app：广角 75°
    // 只改第一视角的相机；切回 orbit/top 时 setMode 会还原 55°
    if (mode === 'first') {
      camera.fov = fpFov;
      camera.updateProjectionMatrix();
    }
  }
  function applyEye() {
    var v = parseFloat(eyeSl.value);
    if (!isFinite(v)) v = 1.6;
    fpEye = Math.max(0.5, Math.min(3, v));
    eyeVal.textContent = fpEye.toFixed(1) + 'm';
    if (mode === 'first') fpPos.y = fpEye; // 只影响第一视角玩家高度
  }
  if (fovSl) fovSl.addEventListener('input', applyFov);
  if (eyeSl) eyeSl.addEventListener('input', applyEye);
  if (fovVal) fovVal.textContent = Math.round(fpFov) + '°';
  if (eyeVal) eyeVal.textContent = fpEye.toFixed(1) + 'm';

  // ---------- 第一视角方向键（D-pad）：按住定向 → 写 moveVec，松手复位 ----------
  // moveVec 由主循环按 fpYaw 换算成 mx/mz（这部分是原摇杆的老算法，保持不动）。
  // 关键：主循环的 fx/fz = (-sin,-cos) 与相机视线 (sin,cos) 相差 180°（见 drawMini
  // 注释），如果照搬摇杆的正负号，按「上」会背对画面后退。所以这里按**视线**方向
  // 取反映射：上=向画面里走、下=后退、右=画面右手侧移、左=左手侧移。
  var dpad = document.getElementById('dpad');
  var DP_DIR = { up: [0, 1], down: [0, -1], left: [1, 0], right: [-1, 0] };
  var dpActive = null;
  function setDpad(id) {
    var d = id ? DP_DIR[id] : null;
    moveVec.x = d ? d[0] : 0;
    moveVec.z = d ? d[1] : 0;
    ['up', 'down', 'left', 'right'].forEach(function (k) {
      var b = document.getElementById('dp-' + k);
      if (b) b.classList.toggle('on', k === id);
    });
  }
  if (dpad) {
    ['up', 'down', 'left', 'right'].forEach(function (k) {
      var b = document.getElementById('dp-' + k);
      if (!b) return;
      b.addEventListener('pointerdown', function (e) {
        e.preventDefault();
        dpActive = k;
        try { b.setPointerCapture(e.pointerId); } catch (err) {}
        setDpad(k);
      });
      var end = function () {
        if (dpActive !== k) return;
        dpActive = null;
        setDpad(null);
      };
      b.addEventListener('pointerup', end);
      b.addEventListener('pointercancel', end);
      b.addEventListener('lostpointercapture', end);
    });
  }

  // 主循环
  var clock = new THREE.Clock();
  function loop() {
    requestAnimationFrame(loop);
    var dt = Math.min(0.05, clock.getDelta());

    if (mode === 'first') {
      var speed = 1.8 * dt;
      var sin = Math.sin(fpYaw), cos = Math.cos(fpYaw);
      // 前进 = 视线方向（水平）
      var fx = -sin, fz = -cos;
      var rx = cos, rz = -sin;
      var mx = fx * (-moveVec.z) + rx * moveVec.x;
      var mz = fz * (-moveVec.z) + rz * moveVec.x;
      var nx = fpPos.x + mx * speed;
      var nz = fpPos.z + mz * speed;
      var p = collide(nx, nz);
      fpPos.x = p[0];
      fpPos.z = p[1];
      fpPos.y = fpEye; // 人眼高度由滑杆决定（默认 1.6m）
      camera.position.copy(fpPos);
      camera.up.set(0, 1, 0);
      camera.rotation.set(0, 0, 0);
      camera.rotateY(fpYaw + Math.PI);
      camera.rotateX(fpPitch);

      // 小地图节流 10fps 重画（朝向/位置变化平缓，不必每帧清画布）
      var now = (window.performance && performance.now) ? performance.now() : Date.now();
      if (now - miniT >= 100) {
        miniT = now;
        drawMini();
      }
    } else if (controls) {
      controls.update();
    }
    renderer.render(scene, camera);
  }

  function resize() {
    var w = window.innerWidth, h = window.innerHeight;
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    renderer.setSize(w, h);
  }
  window.addEventListener('resize', resize);
  resize();

  controls = new THREE.OrbitControls(camera, renderer.domElement);
  controls.enableDamping = true;
  controls.dampingFactor = 0.08;
  controls.maxPolarAngle = Math.PI * 0.49;
  controls.minDistance = 0.5;
  controls.maxDistance = 60;

  applyLang(); // v0.1.50：初始化覆盖层文案（默认 zh，Dart 随后 setLang 切换）
  loop();
  post({ type: 'ready' });
})();
