#!/usr/bin/env python3
"""2D 平面图俯视轮廓生成器（P1：内置模型；P2 用户素材用同一套参数）。

从 assets/web/models.js（window.JJ_MODELS）与 assets/web/models_ext.js
（window.JJ_EXT_MODELS）里的 OBJ 文本，离线算出每个「地面摆放」模型的俯视
矢量轮廓，写进 lib/features/floorplan/domain/model_silhouettes.dart。

输出形状（与 dart domain/silhouette.dart 的 ModelSilhouette 对应）：
  'o': [[u,v, ...], ...]   外轮廓，可多条闭环（模型由多块不相连碎件组成时每块一条），
                           0..1（u=宽向 X，v=深向 Z），CCW
  'h': [[u,v, ...], ...]   孔洞闭环，CW；面积 <1% 的碎洞丢弃
  'l': [[u1,v1,u2,v2], ...] 内部主分隔线（归一化坐标）

参数（P2 的 Dart 实现必须同值，见 silhouette.dart 顶部常量注释）：
  栅格 128×128、逐三角重心填充、DP ε=0.5px、外轮廓 ≤80 点 / 孔 ≤40 点、
  内部线：两面共享边且两面 n.y>0.2、投影长 0.05..0.9、距外形 <0.02 丢弃、
  近平行重合（中点距 <0.015 且方向夹角 <8°）合并、最多 16 条、
  孔洞面积 <1% 总面积丢弃、外形 bbox 自检 ±0.01。

与规格文字的差异（都有实测依据，改前先看这里）：
  · 「上向面质心 y 标准差 > 2.5%×h」这条有机判定在真实素材上会误杀全部 76 件：
    这些 OBJ 绕向不统一（内翻面/单面片），n.y>0.2 会把底面和侧面也算成上向面，
    任何多高度实体都超阈值。改用**顶面杂乱**的可测信号：两面共享的候选分隔边
    > 60 条，或保留线数直接打满 16 条 → lines=[] 整件跳过（树冠/绿植/喷泉/
    软包沙发这类）。ystd 仍写进报表供参考。
  · 碎件：先做闭运算（膨胀→腐蚀，补 0 边）桥接发丝缝，再按绕向分类；
    CCW 环都是外轮廓（多块 → 多条 'o'），CW 环才是孔洞。
  · 栅格填充给 0.5px 容差（像素中心到三角形距离）：栏杆 65mm、画框 16mm 这类
    细条否则整条落在像素中心之间被漏掉。
  · 内部线排除共面共享边（|dot(n1,n2)|>0.9995）：同一平板被拆成两个三角的
    对角线不是分隔线。

只处理 floor 摆放类：models.js 里 cat != 门 的 23 条 + model_items.dart 里
place=floor 且带 modelId 的 53 条（11 庭院 + 42 家具）= 76 条。门窗一律不生成。

用法：python3 tool/silhouette_gen.py [--check]
退出码 0 = 生成成功且自检通过。
"""
import argparse
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DART = os.path.join(ROOT, "lib", "features", "floorplan", "domain",
                        "model_silhouettes.dart")
OUT_REPORT = os.path.join(ROOT, "tool", "silhouette_report.txt")

# ---- 算法参数（改动必须同步 silhouette.dart 的同名常量）----
GRID = 128
RASTER_TOL = 0.5             # 像素中心距三角形 ≤0.5px 即算覆盖（细条不丢）
DP_EPS_PX = 0.5
MAX_OUTER_PTS = 80
MAX_HOLE_PTS = 40
MIN_HOLE_AREA = 0.01          # 孔洞占总面积比例，低于此丢弃（小碎洞）
MIN_OUTER_AREA = 0.002        # 碎件外形占总面积比例（比孔洞宽松，保住伸出的小尖角）
MAX_OUTER_LOOPS = 12          # 多块外形最多保留的环形数
LINE_MIN_LEN = 0.05
LINE_MAX_LEN = 0.9
LINE_EDGE_DIST = 0.02
LINE_MERGE_DIST = 0.015
LINE_MERGE_DOT = 0.99         # 夹角 < ~8°
LINE_MAX = 16
UP_NY = 0.2
ORGANIC_STD = 0.025           # × h（仅报表参考；见 ORGANIC_CAND）
ORGANIC_CAND = 60             # 候选分隔边 > 此数 → 顶面杂乱，lines=[]
BBOX_TOL = 0.01


# ------------------------------------------------------------------ 读源数据
def load_js_map(path, var):
    """从 JS 文件里取出 window.<var> = {...}; 的 JSON 主体（两文件均为纯 JSON）。"""
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    i = text.index("window." + var)
    body = text[text.index("{", i):]
    body = body.rstrip()
    if body.endswith(";"):
        body = body[:-1].rstrip()
    return json.loads(body)


def floor_model_ids():
    """model_items.dart 里 place=floor 且有 modelId 的条目 id。"""
    src = open(os.path.join(ROOT, "lib", "features", "floorplan", "domain",
                            "model_items.dart"), "r", encoding="utf-8").read()
    out = []
    for b in re.findall(r"ModelSpec\((.*?)\n    \),", src, re.S):
        if "place: ModelPlace.floor" not in b:
            continue
        m = re.search(r"modelId: '([^']+)'", b)
        if m:
            out.append(m.group(1))
    return out


# ------------------------------------------------------------------ OBJ 解析
def parse_obj(text):
    """返回 (verts, tris)。f 允许 v/vt/vn、v//vn、负索引。"""
    verts = []
    tris = []
    for raw in text.split("\n"):
        line = raw.strip()
        if not line or line[0] == "#":
            continue
        if line[0] == "v" and line[1:2] in (" ", "\t"):
            p = line.split()
            if len(p) < 4:
                continue
            try:
                verts.append((float(p[1]), float(p[2]), float(p[3])))
            except ValueError:
                continue
        elif line[0] == "f" and line[1:2] in (" ", "\t"):
            p = line.split()[1:]
            if len(p) < 3:
                continue
            idx = []
            for a in p:
                s = a.split("/")[0]
                try:
                    n = int(s)
                except ValueError:
                    continue
                idx.append(n - 1 if n > 0 else len(verts) + n)
            for k in range(1, len(idx) - 1):
                tris.append((idx[0], idx[k], idx[k + 1]))
    return verts, tris


# ------------------------------------------------------------------ 栅格化
def rasterize(verts, tris, w, d, minx, minz):
    """逐三角重心法填充 128×128。网格单元 (i,j)：u=i/N..(i+1)/N, v=j/N..(j+1)/N。"""
    g = bytearray(GRID * GRID)
    inv_w = GRID / w
    inv_d = GRID / d
    for (a, b, c) in tris:
        try:
            va, vb, vc = verts[a], verts[b], verts[c]
        except IndexError:
            continue
        ax = (va[0] - minx) * inv_w
        ay = (va[2] - minz) * inv_d
        bx = (vb[0] - minx) * inv_w
        by = (vb[2] - minz) * inv_d
        cx = (vc[0] - minx) * inv_w
        cy = (vc[2] - minz) * inv_d
        area = (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
        if abs(area) < 1e-12:
            continue
        s = 1.0 if area > 0 else -1.0
        # 每条边的容差 = 0.5px × 边在像素坐标系里的长度（等价于中心距边 ≤0.5px）
        t0 = RASTER_TOL * math.hypot(bx - ax, by - ay) * s
        t1 = RASTER_TOL * math.hypot(cx - bx, cy - by) * s
        t2 = RASTER_TOL * math.hypot(ax - cx, ay - cy) * s
        i0 = max(0, int(math.floor(min(ax, bx, cx))))
        i1 = min(GRID - 1, int(math.ceil(max(ax, bx, cx))))
        j0 = max(0, int(math.floor(min(ay, by, cy))))
        j1 = min(GRID - 1, int(math.ceil(max(ay, by, cy))))
        # 判定用「像素中心到三角形」的近似距离：留 RASTER_TOL 像素容差，
        # 否则细条（栏杆 65mm、画框 16mm、树枝）会整条落在像素中心之间被漏掉。
        for j in range(j0, j1 + 1):
            py = j + 0.5
            row = j * GRID
            for i in range(i0, i1 + 1):
                px = i + 0.5
                e0 = ((bx - ax) * (py - ay) - (by - ay) * (px - ax)) * s
                if e0 < -t0:
                    continue
                e1 = ((cx - bx) * (py - by) - (cy - by) * (px - bx)) * s
                if e1 < -t1:
                    continue
                e2 = ((ax - cx) * (py - cy) - (ay - cy) * (px - cx)) * s
                if e2 < -t2:
                    continue
                g[row + i] = 1
    return g


# ------------------------------------------------------------------ 形态学闭运算
def _filt(g, r, mode):
    """可分离方形滤波（mode='max' 膨胀 / 'min' 腐蚀）。

    先补 r 圈 0 再滤、滤完裁掉：否则膨胀在数组边界被裁、腐蚀再往里收，
    整体外形会缩进 r 像素（薄边/外形 bbox 自检会因此偏小）。
    """
    n = GRID + 2 * r
    pad = bytearray(n * n)
    for j in range(GRID):
        o = (j + r) * n + r
        pad[o:o + GRID] = g[j * GRID:(j + 1) * GRID]
    tmp = bytearray(n * n)
    zero = 0 if mode == "max" else 1
    for j in range(n):
        row = j * n
        for i in range(n):
            best = zero
            for k in range(max(0, i - r), min(n, i + r + 1)):
                v = pad[row + k]
                if mode == "max":
                    if v > best:
                        best = v
                elif v < best:
                    best = v
            tmp[row + i] = best
    out = bytearray(GRID * GRID)
    for i in range(GRID):
        for j in range(GRID):
            best = zero
            for k in range(max(0, j), min(n, j + 2 * r + 1)):
                v = tmp[k * n + i + r]
                if mode == "max":
                    if v > best:
                        best = v
                elif v < best:
                    best = v
            out[j * GRID + i] = best
    return out


def closing(g, r):
    """闭运算：先膨胀再腐蚀 → 桥接 <2r 的裂缝/碎件，外沿不长大。"""
    if r <= 0:
        return g
    return _filt(_filt(g, r, "max"), r, "min")


# ------------------------------------------------------------------ 轮廓追踪
def trace_loops(g):
    """格子边界追踪：填充区在左 → 外轮廓 CCW、孔洞 CW（自动）。"""
    edges = {}   # start vertex -> list of end vertices
    used = set()

    def add(p, q):
        edges.setdefault(p, []).append(q)

    F = lambda i, j: (0 <= i < GRID and 0 <= j < GRID and g[j * GRID + i] == 1)
    for j in range(GRID):
        for i in range(GRID):
            if not g[j * GRID + i]:
                continue
            if not F(i, j - 1):
                add((i, j), (i + 1, j))          # 下边 +u
            if not F(i + 1, j):
                add((i + 1, j), (i + 1, j + 1))  # 右边 +v
            if not F(i, j + 1):
                add((i + 1, j + 1), (i, j + 1))  # 上边 -u
            if not F(i - 1, j):
                add((i, j + 1), (i, j))          # 左边 -v

    loops = []
    for start in list(edges.keys()):
        while edges.get(start):
            # 取一条未用边起步
            p = start
            nxts = [q for q in edges[p] if (p, q) not in used]
            if not nxts:
                break
            loop = [p]
            prev_dir = None
            q = nxts[0]
            used.add((p, q))
            loop.append(q)
            p, prev = q, p
            while p != start:
                cand = [r for r in edges.get(p, []) if (p, r) not in used]
                if not cand:
                    break
                if len(cand) > 1 and prev_dir is not None:
                    # 对角相接的歧义点：取最靠左转的边（填充分成 4 连通）
                    def turn(r):
                        dx, dy = r[0] - p[0], r[1] - p[1]
                        cross = prev_dir[0] * dy - prev_dir[1] * dx
                        dot = prev_dir[0] * dx + prev_dir[1] * dy
                        return math.atan2(cross, dot)
                    cand.sort(key=turn, reverse=True)
                r = cand[0]
                used.add((p, r))
                loop.append(r)
                prev_dir = (r[0] - p[0], r[1] - p[1])
                p = r
            if len(loop) >= 4:
                loops.append(loop[:-1])
    return loops


def signed_area(loop):
    s = 0.0
    n = len(loop)
    for k in range(n):
        x1, y1 = loop[k]
        x2, y2 = loop[(k + 1) % n]
        s += x1 * y2 - x2 * y1
    return s / 2.0


def dp(pts, eps):
    """Douglas-Peucker（开链，首尾固定）。"""
    if len(pts) < 3:
        return list(pts)
    keep = [False] * len(pts)
    keep[0] = keep[-1] = True
    stack = [(0, len(pts) - 1)]
    while stack:
        a, b = stack.pop()
        if b <= a + 1:
            continue
        ax, ay = pts[a]
        bx, by = pts[b]
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        best, bi = -1.0, -1
        for k in range(a + 1, b):
            px, py = pts[k]
            if L2 < 1e-12:
                dist = math.hypot(px - ax, py - ay)
            else:
                t = ((px - ax) * dx + (py - ay) * dy) / L2
                t = max(0.0, min(1.0, t))
                dist = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
            if dist > best:
                best, bi = dist, k
        if best > eps and bi > 0:
            keep[bi] = True
            stack.append((a, bi))
            stack.append((bi, b))
    return [pts[k] for k in range(len(pts)) if keep[k]]


def dp_closed(pts, eps, cap):
    """闭环简化：切成两条开链分别 DP；超点数则加大 ε 重试。"""
    if len(pts) <= 3:
        return pts
    # 取距质心最远的点 a，再取距 a 最远的点 b，切成 [a..b] + [b..a]
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    a = max(range(len(pts)), key=lambda k: (pts[k][0] - cx) ** 2 + (pts[k][1] - cy) ** 2)
    b = max(range(len(pts)), key=lambda k: (pts[k][0] - pts[a][0]) ** 2 + (pts[k][1] - pts[a][1]) ** 2)
    if a > b:
        a, b = b, a
    ch1 = pts[a:b + 1]
    ch2 = pts[b:] + pts[:a + 1]
    e = eps
    out = s1 = s2 = []
    for _ in range(12):
        s1 = dp(ch1, e)
        s2 = dp(ch2, e)
        out = s1[:-1] + s2[:-1]
        if len(out) <= cap:
            return out
        e *= 1.7
    return out[:cap]


# ------------------------------------------------------------------ 内部线
def normals(verts, tris):
    ns = []
    for (a, b, c) in tris:
        try:
            va, vb, vc = verts[a], verts[b], verts[c]
        except IndexError:
            ns.append(None)
            continue
        ux, uy, uz = vb[0] - va[0], vb[1] - va[1], vb[2] - va[2]
        wx, wy, wz = vc[0] - va[0], vc[1] - va[1], vc[2] - va[2]
        nx = uy * wz - uz * wy
        ny = uz * wx - ux * wz
        nz = ux * wy - uy * wx
        ln = math.sqrt(nx * nx + ny * ny + nz * nz)
        if ln < 1e-12:
            ns.append(None)
        else:
            ns.append((nx / ln, ny / ln, nz / ln))
    return ns


def organic_std(verts, tris, ns):
    ys = []
    for t, n in zip(tris, ns):
        if n is None or n[1] <= UP_NY:
            continue
        try:
            ys.append((verts[t[0]][1] + verts[t[1]][1] + verts[t[2]][1]) / 3.0)
        except IndexError:
            continue
    if not ys or len(ys) < 2:
        return 0.0
    m = sum(ys) / len(ys)
    return math.sqrt(sum((y - m) ** 2 for y in ys) / len(ys))


def seg_dist_point(p, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    if L2 < 1e-12:
        return math.hypot(p[0] - ax, p[1] - ay)
    t = ((p[0] - ax) * dx + (p[1] - ay) * dy) / L2
    t = max(0.0, min(1.0, t))
    return math.hypot(p[0] - (ax + t * dx), p[1] - (ay + t * dy))


def poly_dist(p, loops):
    """点到一组闭环（每条都是点列表）的最近距离。"""
    best = 1e9
    for poly in loops:
        n = len(poly)
        for k in range(n):
            d = seg_dist_point(p, poly[k], poly[(k + 1) % n])
            if d < best:
                best = d
    return best


def internal_lines(verts, tris, ns, w, d, minx, minz, outer_loops):
    """两面共享边 + 双上向面 → 投影成归一化线段。"""
    emap = {}
    for ti, (a, b, c) in enumerate(tris):
        for e in ((a, b), (b, c), (c, a)):
            k = (e[0], e[1]) if e[0] < e[1] else (e[1], e[0])
            emap.setdefault(k, []).append(ti)
    cand = []
    for k, ts in emap.items():
        if len(ts) != 2:
            continue
        n1, n2 = ns[ts[0]], ns[ts[1]]
        if n1 is None or n2 is None:
            continue
        if n1[1] <= UP_NY or n2[1] <= UP_NY:
            continue
        # 共面（同一块平板被拆成两个三角）→ 三角化对角线，不是分隔线
        if n1[0] * n2[0] + n1[1] * n2[1] + n1[2] * n2[2] > 0.9995:
            continue
        try:
            p1, p2 = verts[k[0]], verts[k[1]]
        except IndexError:
            continue
        u1 = (p1[0] - minx) / w
        v1 = (p1[2] - minz) / d
        u2 = (p2[0] - minx) / w
        v2 = (p2[2] - minz) / d
        L = math.hypot(u2 - u1, v2 - v1)
        if L < LINE_MIN_LEN or L > LINE_MAX_LEN:
            continue
        mid = ((u1 + u2) / 2, (v1 + v2) / 2)
        if (poly_dist(mid, outer_loops) < LINE_EDGE_DIST or
                poly_dist((u1, v1), outer_loops) < LINE_EDGE_DIST or
                poly_dist((u2, v2), outer_loops) < LINE_EDGE_DIST):
            continue
        cand.append((L, (u1, v1, u2, v2), mid))
    n_cand = len(cand)
    cand.sort(key=lambda t: -t[0])
    kept = []
    for L, seg, mid in cand:
        dup = False
        dx, dy = seg[2] - seg[0], seg[3] - seg[1]
        ln = math.hypot(dx, dy) or 1.0
        dx, dy = dx / ln, dy / ln
        for kL, kseg, kmid in kept:
            if math.hypot(mid[0] - kmid[0], mid[1] - kmid[1]) >= LINE_MERGE_DIST:
                continue
            kdx, kdy = kseg[2] - kseg[0], kseg[3] - kseg[1]
            kln = math.hypot(kdx, kdy) or 1.0
            kdx, kdy = kdx / kln, kdy / kln
            if abs(dx * kdx + dy * kdy) > LINE_MERGE_DOT:
                dup = True
                break
        if dup:
            continue
        kept.append((L, seg, mid))
        if len(kept) >= LINE_MAX:
            break
    return [s for _, s, _ in kept], n_cand


# ------------------------------------------------------------------ 单件
def build(entry):
    obj = entry["o"]
    verts, tris = parse_obj(obj)
    if not verts or not tris:
        raise ValueError("空几何")
    xs = [v[0] for v in verts]
    zs = [v[2] for v in verts]
    ys = [v[1] for v in verts]
    minx, maxx = min(xs), max(xs)
    minz, maxz = min(zs), max(zs)
    h = max(ys) - min(ys)
    w = maxx - minx
    d = maxz - minz
    if w < 1e-9 or d < 1e-9:
        raise ValueError("X/Z 跨度为 0（w=%.4g d=%.4g）" % (w, d))

    g = rasterize(verts, tris, w, d, minx, minz)
    filled = sum(g)
    if filled == 0:
        raise ValueError("栅格空")

    # 模型常由多块互不相连的碎件组成（玻璃片、单面片、树枝、栏杆立柱）：
    # 每条闭合环按绕向分类 —— CCW = 外轮廓（多块就写多条 'o'），CW = 孔洞。
    # 闭运算只用来桥接 <2r 的发丝缝（不让轮廓碎成毛刺），不外扩外形。
    min_hole_px = MIN_HOLE_AREA * filled
    min_out_px = MIN_OUTER_AREA * filled

    def classify(gc):
        out = []
        holes = []
        for lp in trace_loops(gc):
            a = signed_area(lp)
            if a > 0:
                if abs(a) >= min_out_px:
                    out.append(lp)
            elif abs(a) >= min_hole_px:
                holes.append(lp)
        return out, holes

    best = None
    for r in range(0, 4):
        o, hh = classify(closing(g, r))
        if best is None or len(o) < len(best[2]):
            best = (o, hh, o)
        if len(o) == 1:
            break
    outer_px, holes_px, _ = best
    close_r = r
    if not outer_px:
        raise ValueError("无轮廓")

    def to_uv(loop):
        return [(min(1.0, max(0.0, p[0] / GRID)), min(1.0, max(0.0, p[1] / GRID)))
                for p in loop]

    # 外轮廓每条环 CCW（追踪已保证，兜底修正）
    outer = []
    for lp in sorted(outer_px, key=lambda l: -abs(signed_area(l)))[:MAX_OUTER_LOOPS]:
        if signed_area(lp) < 0:
            lp = lp[::-1]
        outer.append(to_uv(dp_closed(lp, DP_EPS_PX, MAX_OUTER_PTS)))

    holes = []
    for hp in sorted(holes_px, key=lambda l: -abs(signed_area(l))):
        if len(holes) >= 8:      # 小碎洞已在面积阈值前拦掉，这里只兜上限
            break
        holes.append(to_uv(dp_closed(hp, DP_EPS_PX, MAX_HOLE_PTS)))

    outer_loops = outer                     # 供内部线距边过滤用

    ns = normals(verts, tris)
    ystd = organic_std(verts, tris, ns)
    # 顶面杂乱判定（替代规格里的 ystd 阈值，理由见文件头注释）：
    # 候选分隔边爆炸 = 顶面由无数碎面拼成（沙发靠垫/软包/喷泉/树冠），线条画出来是乱码。
    lines, n_cand = internal_lines(verts, tris, ns, w, d, minx, minz, outer_loops)
    organic = n_cand > ORGANIC_CAND or len(lines) >= LINE_MAX
    if organic:
        lines = []

    bx = [p[0] for lp in outer for p in lp]
    bv = [p[1] for lp in outer for p in lp]
    bbox_err = max(abs(min(bx)), abs(min(bv)), abs(1 - max(bx)), abs(1 - max(bv)))
    return {
        "id": entry["id"],
        "faces": len(tris),
        "verts": len(verts),
        "outer": outer,
        "holes": holes,
        "lines": lines,
        "organic": organic,
        "cand": n_cand,
        "close_r": close_r,
        "ystd": ystd,
        "bbox_err": bbox_err,
        "w": w, "d": d, "h": h,
    }


# ------------------------------------------------------------------ 输出
def q(x):
    """4 位小数；-0 归 0。"""
    v = round(x, 4)
    return 0.0 if v == 0 else v


def fmt_list(pairs):
    return "[" + ", ".join("%g" % q(c) for p in pairs for c in p) + "]"


def write_dart(results):
    lines = []
    lines.append("// 由 tool/silhouette_gen.py 生成，勿手改。")
    lines.append("//")
    lines.append("// 2D 平面图俯视轮廓（P1 内置模型）：外轮廓 + 内部主分隔线，矢量非贴图。")
    lines.append("// 坐标 0..1：u = 宽向 X，v = 深向 Z（three.js Y-up；top 视图 X→右、Z→下）。")
    lines.append("// 'o' 外轮廓（CCW，可多条：多块碎件各一条）/ 'h' 孔洞（CW，与外形反向）/")
    lines.append("// 'l' 内部主分隔线 [u1,v1,u2,v2]。")
    lines.append("// 只含 floor 摆放类模型：models.js cat!=门 的 23 条 + model_items.dart")
    lines.append("// place=floor 带 modelId 的 53 条（11 庭院 + 42 家具）；门窗不在此表。")
    lines.append("import 'silhouette.dart';")
    lines.append("")
    lines.append("// 数据形状 / 路径构建都在 silhouette.dart，这里顺带导出（调用方一个 import 够）")
    lines.append("export 'silhouette.dart';")
    lines.append("")
    lines.append("const Map<String, Map<String, dynamic>> modelSilhouettes = {")
    for r in results:
        lines.append("  '%s': {" % r["id"])
        os_ = ", ".join(fmt_list(lp) for lp in r["outer"])
        lines.append("    'o': [%s]," % os_)
        if r["holes"]:
            hs = ", ".join(fmt_list(h) for h in r["holes"])
            lines.append("    'h': [%s]," % hs)
        else:
            lines.append("    'h': [],")
        if r["lines"]:
            ls = ", ".join("[" + ", ".join("%g" % q(c) for c in s) + "]"
                           for s in r["lines"])
            lines.append("    'l': [%s]," % ls)
        else:
            lines.append("    'l': [],")
        lines.append("  },")
    lines.append("};")
    lines.append("")
    lines.append("/// 内存缓存：painter 每帧调用，解析结果复用（null 也缓存）。")
    lines.append("final Map<String, ModelSilhouette?> _cache = <String, ModelSilhouette?>{};")
    lines.append("")
    lines.append("/// 查表构造轮廓；缺条目 / 解析失败 → null（画布回落 RRect）。")
    lines.append("ModelSilhouette? silhouetteFor(String? modelId) {")
    lines.append("  if (modelId == null) return null;")
    lines.append("  if (_cache.containsKey(modelId)) return _cache[modelId];")
    lines.append("  final raw = modelSilhouettes[modelId];")
    lines.append("  ModelSilhouette? out;")
    lines.append("  if (raw != null) {")
    lines.append("    try {")
    lines.append("      out = ModelSilhouette.fromJson(raw);")
    lines.append("    } catch (_) {")
    lines.append("      out = null;")
    lines.append("    }")
    lines.append("  }")
    lines.append("  _cache[modelId] = out;")
    lines.append("  return out;")
    lines.append("}")
    lines.append("")
    with open(OUT_DART, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def write_report(results, total, skipped):
    out = []
    out.append("2D 俯视轮廓生成报告（tool/silhouette_gen.py）")
    out.append("参数：栅格 %d×%d, DP ε=%.1fpx, 外≤%d/孔≤%d, 线 %d..%.2f, "
               "距边<%.2f 丢, 合并<%.3f, 线≤%d, 顶面杂乱=cand>%d 或线满"
               % (GRID, GRID, DP_EPS_PX, MAX_OUTER_PTS, MAX_HOLE_PTS,
                  LINE_MIN_LEN, LINE_MAX_LEN, LINE_EDGE_DIST, LINE_MERGE_DIST,
                  LINE_MAX, ORGANIC_CAND))
    out.append("条目：%d" % len(results))
    out.append("")
    out.append("%-22s %6s %6s %4s %4s %4s %4s %6s  %s" %
               ("id", "faces", "verts", "outP", "holes", "lineP", "clR", "ystd/h", "note"))
    organic = []
    badbbox = []
    for r in results:
        yr = (r["ystd"] / r["h"]) if r["h"] > 0 else 0.0
        note = []
        if r["organic"]:
            note.append("顶面杂乱跳过(cand=%d%s)" %
                        (r["cand"], ",线满16" if r["cand"] <= ORGANIC_CAND else ""))
            organic.append(r["id"])
        if len(r["outer"]) > 1:
            note.append("多块外形 x%d" % len(r["outer"]))
        if r["bbox_err"] > BBOX_TOL:
            note.append("bbox偏差 %.3f !!" % r["bbox_err"])
            badbbox.append((r["id"], r["bbox_err"]))
        if not r["lines"] and not r["organic"]:
            note.append("无线")
        out.append("%-22s %6d %6d %4d %4d %4d %4d %6.3f  %s" %
                   (r["id"], r["faces"], r["verts"],
                    sum(len(lp) for lp in r["outer"]),
                    len(r["holes"]), len(r["lines"]), r["close_r"], yr,
                    " ".join(note)))
    out.append("")
    out.append("顶面杂乱整件跳过（lines=[]，cand>%d）：%d 件" % (ORGANIC_CAND, len(organic)))
    out.append("  " + ", ".join(organic))
    out.append("")
    if badbbox:
        out.append("bbox 自检越界（需人工看）：")
        for i, e in badbbox:
            out.append("  %s 误差 %.4f" % (i, e))
    else:
        out.append("bbox 自检：全部外轮廓 bbox ≈ [0,1]²（±%.2f）" % BBOX_TOL)
    if skipped:
        out.append("")
        out.append("解析失败：")
        for i, e in skipped:
            out.append("  %s: %s" % (i, e))
    out.append("")
    out.append("输出文件：%s（%d 字节）" %
               (os.path.relpath(OUT_DART, ROOT), os.path.getsize(OUT_DART)))
    with open(OUT_REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="只自检不比对（默认行为即生成+自检）")
    ap.parse_args()

    js = load_js_map(os.path.join(ROOT, "assets", "web", "models.js"), "JJ_MODELS")
    ext = load_js_map(os.path.join(ROOT, "assets", "web", "models_ext.js"),
                      "JJ_EXT_MODELS")
    ids = []
    for k, v in js.items():
        if v.get("cat") == "门":
            continue
        ids.append((k, v))
    floor_ids = set(floor_model_ids())
    for k in floor_model_ids():
        if k in ext:
            ids.append((k, ext[k]))
        elif k not in js:
            print("警告：floor 条目 %s 在 models_ext.js 里找不到" % k, file=sys.stderr)
    # 去重保序
    seen = set()
    entries = []
    for k, v in ids:
        if k in seen:
            continue
        seen.add(k)
        entries.append({"id": k, "o": v["o"], "w": v["w"], "d": v["d"], "h": v["h"]})

    results, skipped = [], []
    for e in entries:
        try:
            results.append(build(e))
        except Exception as ex:  # noqa: BLE001 - 单件失败不拖垮整批
            skipped.append((e["id"], repr(ex)))
    results.sort(key=lambda r: r["id"])
    write_dart(results)
    write_report(results, len(entries), skipped)
    size = os.path.getsize(OUT_DART)
    print("生成 %d/%d 条，%d 字节 → %s" % (len(results), len(entries), size, OUT_DART))
    print("报告 → %s" % OUT_REPORT)
    bad = [(r["id"], r["bbox_err"]) for r in results if r["bbox_err"] > BBOX_TOL]
    if bad:
        print("bbox 越界：%s" % bad)
    if skipped:
        print("失败：%s" % skipped)
    if size >= 400 * 1024:
        print("体积超 400KB！需收紧 DP ε 或线条上限", file=sys.stderr)
        return 1
    return 0 if not skipped else 1


if __name__ == "__main__":
    sys.exit(main())
