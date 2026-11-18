/* jiajia 3D 场景：户型 → 三维。单位：米。
 * 数据契约（Dart FloorPlan.toJsonString()）:
 * { name, walls:[{id,ax,ay,bx,by,t,h}], openings:[{id,wall,kind,off,w,sill}],
 *   items:[{id,kind,x,y,rot}] }
 * 桥：window.dart.postMessage(JSON.stringify({type,...}))
 *     Dart 调 window.jiajia.setPlan(jsonStr) / .setMode('top'|'orbit'|'first')
 */
(function () {
  'use strict';

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
  var moveVec = { x: 0, z: 0 }; // 摇杆
  var keys = {};
  var lastPlan = null;
  var doorsDbg = [], windowsDbg = []; // 调试：门窗实体引用

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

  function buildWalls(plan) {
    plan.walls.forEach(function (w) {
      var ax = w.ax, ay = w.ay, bx = w.bx, by = w.by;
      var dx = bx - ax, dy = by - ay;
      var len = Math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) return;
      var ang = Math.atan2(dy, dx); // 平面角 → 3D 绕 Y 轴 = -ang? 平面 y→z
      var th = w.t || 0.24;
      var hh = w.h || 2.8;

      wallAABB.push({ ax: ax, ay: ay, bx: bx, by: by, r: th / 2 + 0.35 });

      wallSegments(w, plan).forEach(function (seg) {
        var t0 = seg[0], t1 = seg[1], kind = seg[2];
        var segLen = len * (t1 - t0);
        if (segLen < 1e-4) return;
        var mx = ax + dx * ((t0 + t1) / 2);
        var my = ay + dy * ((t0 + t1) / 2);

        if (kind === 'solid') {
          var box = wallBox(segLen, hh, th, COL.wall);
          box.position.copy(w2v(mx, my));
          box.position.y = hh / 2;
          box.rotation.y = -ang;
          root.add(box);
        } else if (kind.kind === 'door') {
          // 门洞：上方过梁（墙高 >2.1m 才有）+ 门扇
          if (hh > 2.15) {
            var lintel = wallBox(segLen, hh - 2.1, th, COL.wall);
            lintel.position.copy(w2v(mx, my));
            lintel.position.y = 2.1 + (hh - 2.1) / 2;
            lintel.rotation.y = -ang;
            root.add(lintel);
          }
          // v0.1.18 门扇：单开整宽、双开两端各半宽；铰链在开洞端部，
          // 90° 张开——内开朝法向内侧（side=1）、外开朝外侧（side=-1）
          if (kind.dt === 'single' || kind.dt === 'double') {
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
          // 窗：窗台下实墙 + 玻璃
          var sill = kind.sill || 0.9;
          var below = wallBox(segLen, sill, th, COL.wall);
          below.position.copy(w2v(mx, my));
          below.position.y = sill / 2;
          below.rotation.y = -ang;
          root.add(below);
          var glassH = hh - sill;
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
      var col = mc[matName] != null ? parseInt(mc[matName].slice(1), 16) : model.c;
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

  function buildItems(plan) {
    plan.items.forEach(function (i) {
      // v0.1.20：自定义尺寸（米）→ 目录盒/模型等比缩放
      var sw = (typeof i.sw === 'number') ? i.sw : null;
      var sd = (typeof i.sd === 'number') ? i.sd : null;
      var sh = (typeof i.sh === 'number') ? i.sh : null;
      var modelMid = i.model && window.JJ_MODELS && window.JJ_MODELS[i.model]
          ? i.model : null;
      if (modelMid) {
        var proto = modelGeometry(modelMid);
        if (proto) {
          var mesh = proto.clone(true);
          var md = window.JJ_MODELS[modelMid];
          if (sw != null || sd != null || sh != null) {
            var sx = sw != null && md.w ? sw / md.w : 1;
            var sz = sd != null && md.d ? sd / md.d : 1;
            var sy = sh != null && md.h ? sh / md.h : (sx + sz) / 2;
            mesh.scale.set(sx, sy, sz);
          }
          mesh.position.set(i.x, 0, i.y);
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
      var box = new THREE.Mesh(
          new THREE.BoxGeometry(bw, bh, bd),
          new THREE.MeshStandardMaterial({ color: spec[3] }));
      box.position.set(i.x, bh / 2, i.y);
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

  function applyPlan(jsonStr) {
    clearRoot();
    doorsDbg = []; windowsDbg = [];
    var plan = JSON.parse(jsonStr);
    lastPlan = plan;
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
      fpPos.y = 1.6;
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
    setPlan: applyPlan,
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
    setMode: function (m) {
      mode = m;
      document.getElementById('joy').style.display =
          m === 'first' ? 'block' : 'none';
      document.getElementById('hint').textContent =
          m === 'first' ? '摇杆移动 · 拖动转向'
          : m === 'top' ? '俯视图 · 双指缩放/平移' : '轨道视角 · 拖动旋转';
      var c = lastPlan ? centerOf(lastPlan) : new THREE.Vector3(0, 0, 0);
      if (controls) {
        controls.enabled = m !== 'first';
      }
      if (lastPlan) applyPlan(JSON.stringify(lastPlan));
      post({ type: 'mode', mode: m });
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
      fpPos.y = 1.6;
      camera.position.copy(fpPos);
      camera.up.set(0, 1, 0);
      camera.rotation.set(0, 0, 0);
      camera.rotateY(fpYaw + Math.PI);
      camera.rotateX(fpPitch);
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

  document.getElementById('hint').textContent = '等待户型数据…';
  loop();
  post({ type: 'ready' });
})();
