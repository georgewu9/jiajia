#!/usr/bin/env python3
"""v0.1.36 庭院实模回归探针（v0.1.37 起 11 件：坡道栏杆已删）（无头 Chromium + 本地 http.server，套路同 tool/open_slice_check.py）。

验证：
  1) 11 件 kind=asset + model=m_courtyard_* 地面摆放 → 每件 mesh 顶点 >10（实模不是占位盒）
  2) 世界尺寸 ≈ ModelSpec 规格（米），误差 <0.05m（大面数 greenhouse 也算）
  3) 三角面数（= 非索引 geometry 的顶点数 / 3）与期望表逐个对比
  4) window.JJ_EXT_MODELS 缺席（旧包升级）→ 全部回占位盒，页面不抛异常

用法：python3 tool/courtyard_check.py [--shot out.png]
退出码 0 = 全部通过；1 = 有断言失败（明细打到 stdout 的 JSON）。
"""
import argparse
import json
import os
import subprocess
import sys
import time

ROOT = os.environ.get(
    "JJ_WEB_ROOT",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "assets", "web"))
PORT = 8138

# id → (中文名, w, d, h, 期望三角面数)
SPECS = {
    "m_courtyard_awning": ("遮阳棚支架", 3.10, 1.69, 0.62, 780),
    "m_courtyard_birch": ("白桦", 4.16, 3.86, 7.92, 4498),
    "m_courtyard_chair": ("黑色露台椅", 0.29, 0.37, 0.62, 7182),
    "m_courtyard_table": ("黑色露台桌", 0.91, 0.92, 0.42, 5850),
    "m_courtyard_palm": ("扇叶棕榈", 5.06, 5.68, 6.34, 4498),
    "m_courtyard_fountain": ("庭院喷泉", 1.85, 1.85, 1.50, 4500),
    "m_courtyard_greenhouse": ("温室", 3.10, 3.10, 2.90, 5098),
    "m_courtyard_pine": ("松树", 3.40, 3.76, 6.13, 4500),
    "m_courtyard_railing": ("栏杆", 4.75, 0.33, 1.81, 504),
    "m_courtyard_sassafras": ("马桑树", 1.77, 1.52, 2.07, 5000),
    "m_courtyard_tree": ("庭院树", 7.50, 8.00, 10.00, 4499),
}


def plan():
    items = []
    for i, (mid, (_n, w, d, h, _f)) in enumerate(SPECS.items()):
        items.append({
            "id": "i%d" % i, "kind": "asset", "model": mid,
            "x": (i % 4) * 26.0, "y": (i // 4) * 22.0, "rot": 0,
            "sw": w, "sd": d, "sh": h,
        })
    return {"name": "courtyard12", "walls": [], "openings": [], "items": items}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", default="")
    args = ap.parse_args()

    from playwright.sync_api import sync_playwright

    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT),
                            "-d", ROOT],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    out, errs = {}, []
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=["--enable-unsafe-swiftshader"])
            pg = b.new_page(viewport={"width": 1000, "height": 700},
                            device_scale_factor=1)
            pg.on("pageerror", lambda e: errs.append(str(e)))
            pg.goto(f"http://127.0.0.1:{PORT}/viewer.html")
            pg.wait_for_function(
                "() => !!(window.jiajia && window.jiajia.setPlan &&"
                " window.jiajia.debugItems)")
            pg.evaluate("window.__JJ_EXT_BACKUP = window.JJ_EXT_MODELS")
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))", plan())
            pg.wait_for_timeout(1200)

            dbg = pg.evaluate("window.jiajia.debugItems()")
            by_id = {d["id"]: d for d in dbg}
            rows, failed = [], []
            for i, (mid, (name, w, d, h, faces)) in enumerate(SPECS.items()):
                e = by_id.get("i%d" % i)
                if not e:
                    failed.append(f"{mid}: debugItems 缺条目")
                    continue
                measured_faces = int(round(e["verts"] / 3))
                sz = e["size"]  # [x=w, y=h, z=d]
                dim_ok = (abs(sz[0] - w) < 0.05 and abs(sz[1] - h) < 0.05
                          and abs(sz[2] - d) < 0.05)
                row = {
                    "id": mid, "name": name,
                    "meshes": e["meshes"], "verts": e["verts"],
                    "faces": measured_faces, "faces_expected": faces,
                    "faces_ok": measured_faces == faces,
                    "size": sz, "spec_wdh": [w, h, d], "dim_ok": dim_ok,
                    "placeholder": e["placeholder"],
                    "assert_real_mesh": (not e["placeholder"]
                                         and e["verts"] > 10),
                }
                rows.append(row)
                if not row["assert_real_mesh"]:
                    failed.append(f"{mid}: 占位盒/顶点过少")
                if not row["faces_ok"]:
                    failed.append(f"{mid}: 面数 {measured_faces} != {faces}")
                if not dim_ok:
                    failed.append(f"{mid}: 尺寸 {sz} != {[w, h, d]}")
            out["items"] = rows

            # 4) models_ext.js 缺席 → 占位盒 + 不崩
            pg.evaluate("window.JJ_EXT_MODELS = undefined")
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))", plan())
            pg.wait_for_timeout(800)
            dbg2 = pg.evaluate("window.jiajia.debugItems()")
            out["missing_ext_count"] = len(dbg2)
            out["assert_missing_ext_placeholder"] = bool(
                len(dbg2) == len(SPECS)
                and all(d["placeholder"] and d["label"] for d in dbg2))

            if args.shot:
                pg.evaluate("window.JJ_EXT_MODELS = window.__JJ_EXT_BACKUP")
                pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                            plan())
                pg.wait_for_timeout(800)
                pg.evaluate("window.jiajia.setMode('orbit')")
                pg.wait_for_timeout(400)
                pg.screenshot(path=args.shot)
                out["screenshot"] = args.shot
            b.close()
    finally:
        srv.terminate()

    out["pageerrors"] = errs
    out["assert_no_pageerror"] = len(errs) == 0
    if not out["assert_no_pageerror"]:
        failed.append("pageerror")
    if not out["assert_missing_ext_placeholder"]:
        failed.append("missing_ext: 未回占位盒")
    out["failed"] = failed
    out["ok"] = not failed
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
