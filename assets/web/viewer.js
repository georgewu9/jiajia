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
  };

  var scene = new THREE.Scene();
  scene.background = new THREE.Color(0x0e1117);
  scene.fog = new THREE.Fog(0x0e1117, 30, 80);

  var camera = new THREE.PerspectiveCamera(
      55, 1, 0.05, 200);
  var renderer = new THREE.WebGLRenderer({
      canvas: document.getElementById('c'),
      antialias: true
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

  // 灯光
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));
  var sun = new THREE.DirectionalLight(0xfff2d8, 0.9);
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
        new THREE.MeshStandardMaterial({ color: 0x1b222c }));
    floor.position.set(cx, -0.025, cz);
    root.add(floor);

    var grid = new THREE.GridHelper(40, 80, 0x2a3140, 0x1a202b);
    grid.position.y = 0.001;
    root.add(grid);
  }

  function wallSegments(wall, plan) {
    // 与 Dart 侧一致：开洞分段 [(t0,t1,solid)]
    var opens = plan.openings
        .filter(function (o) { return o.wall === wall.id; })
        .map(function (o) {
          var len = wall.length || 1;
          return [o.off / len, (o.off + o.w) / len, o];
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
          var box = new THREE.Mesh(
              new THREE.BoxGeometry(segLen, hh, th),
              new THREE.MeshStandardMaterial({ color: 0x44506a }));
          box.position.copy(w2v(mx, my));
          box.position.y = hh / 2;
          box.rotation.y = -ang;
          root.add(box);
        } else if (kind.kind === 'door') {
          // 门洞：上方过梁 + 地板上的门扇弧线提示
          var lintel = new THREE.Mesh(
              new THREE.BoxGeometry(segLen, hh - 2.1, th),
              new THREE.MeshStandardMaterial({ color: 0x44506a }));
          lintel.position.copy(w2v(mx, my));
          lintel.position.y = 2.1 + (hh - 2.1) / 2;
          lintel.rotation.y = -ang;
          root.add(lintel);
        } else if (kind.kind === 'window') {
          // 窗：窗台下实墙 + 玻璃
          var sill = kind.sill || 0.9;
          var below = new THREE.Mesh(
              new THREE.BoxGeometry(segLen, sill, th),
              new THREE.MeshStandardMaterial({ color: 0x44506a }));
          below.position.copy(w2v(mx, my));
          below.position.y = sill / 2;
          below.rotation.y = -ang;
          root.add(below);
          var glassH = hh - sill;
          var glass = new THREE.Mesh(
              new THREE.BoxGeometry(segLen, glassH, 0.04),
              new THREE.MeshStandardMaterial({
                color: 0x87ceeb, transparent: true, opacity: 0.35,
                side: THREE.DoubleSide
              }));
          glass.position.copy(w2v(mx, my));
          glass.position.y = sill + glassH / 2;
          glass.rotation.y = -ang;
          root.add(glass);
        }
      });
    });
  }

  function buildItems(plan) {
    plan.items.forEach(function (i) {
      var spec = CATALOG[i.kind];
      if (!spec) return;
      var box = new THREE.Mesh(
          new THREE.BoxGeometry(spec[0], spec[2], spec[1]),
          new THREE.MeshStandardMaterial({ color: spec[3] }));
      box.position.set(i.x, spec[2] / 2, i.y);
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
