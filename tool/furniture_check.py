#!/usr/bin/env python3
"""v0.1.37 家具 42 件实模回归探针（无头 Chromium + 本地 http.server，套路同 tool/courtyard_check.py）。

验证：
  1) 42 件 kind=asset + model=m_furn_* 地面摆放 → 每件 mesh 顶点 >10（实模不是占位盒）
  2) 世界尺寸 ≈ ModelSpec 规格（米），误差 <0.05m
  3) 三角面数（= 非索引 geometry 顶点数 / 3）与 manifest 面数逐个对比并打印
  4) window.JJ_EXT_MODELS 缺席（旧包升级）→ 全部回占位盒，页面不抛异常
  5) 离地高度：awning 物品 off=1500 → bbox 底面 y≈1.5m；未带 off 的家具 y≈0m

用法：python3 tool/furniture_check.py [--shot out.png]
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
PORT = 8139

# id → (中文名, w, d, h, 期望三角面数 = manifest.json 的 faces)
SPECS = {
    "m_furn_armoire": ("衣柜", 1.795, 0.675, 2.214, 860),
    "m_furn_office_chair": ("办公椅", 0.480, 0.495, 0.870, 321),
    "m_furn_desk": ("书桌", 1.400, 0.591, 0.758, 316),
    "m_furn_stool": ("坐凳", 0.458, 0.448, 0.790, 4498),
    "m_furn_cappa": ("烟罩（cappa，待认）", 0.811, 0.610, 0.750, 76),
    "m_furn_flowers": ("插花", 0.392, 0.297, 0.938, 4500),
    "m_furn_fridge_2": ("冰箱", 0.611, 0.738, 2.221, 124),
    "m_furn_piano": ("立式钢琴", 2.880, 1.140, 2.220, 160),
    "m_furn_potplant": ("盆栽", 0.967, 0.962, 0.854, 4506),
    "m_furn_refrigerator": ("冰箱", 0.675, 0.574, 1.476, 574),
    "m_furn_piano_stool": ("钢琴凳", 0.720, 0.760, 0.970, 156),
    "m_furn_frame_vatican": ("画框", 0.612, 0.016, 0.479, 112),
    "m_furn_frame_yosemite": ("画框", 0.735, 0.016, 0.479, 112),
    "m_furn_washer_dryer": ("洗烘一体", 0.595, 0.550, 0.850, 1216),
    "m_furn_upper_cab_2d": ("双门吊柜", 0.675, 0.393, 0.600, 3294),
    "m_furn_dresser": ("斗柜", 1.436, 0.485, 0.642, 612),
    "m_furn_bed": ("双人床", 1.840, 1.970, 0.650, 1028),
    "m_furn_pantry": ("食品柜", 0.835, 0.542, 1.569, 674),
    "m_furn_lower_cab_1d": ("单门地柜", 0.394, 0.564, 0.654, 4940),
    "m_furn_upper_cab_1d": ("单门吊柜", 0.339, 0.393, 0.600, 2514),
    "m_furn_lower_cab_2d": ("双门地柜", 0.729, 0.564, 0.654, 4498),
    "m_furn_cab_3draw": ("三抽柜", 0.393, 0.643, 0.641, 4500),
    "m_furn_shower_tray": ("淋浴底盘", 0.900, 0.900, 0.065, 568),
    "m_furn_vanity": ("浴室柜", 1.220, 0.550, 0.780, 716),
    "m_furn_jacuzzi": ("按摩浴缸", 1.600, 0.700, 0.580, 4032),
    "m_furn_corner_cab": ("转角柜", 0.330, 0.437, 0.340, 380),
    "m_furn_shower_room": ("淋浴房", 0.700, 0.700, 2.000, 3622),
    "m_furn_hob": ("燃气灶", 0.600, 0.400, 0.031, 4499),
    "m_furn_island": ("中岛", 1.318, 0.587, 0.567, 4500),
    "m_furn_marble_sink": ("大理石水槽柜", 1.118, 0.852, 1.611, 4499),
    "m_furn_mirror": ("镜子", 0.501, 0.010, 0.701, 100),
    "m_furn_shower_cabin": ("淋浴间", 0.900, 0.900, 1.990, 1401),
    "m_furn_toilet": ("壁挂马桶", 0.380, 0.565, 0.820, 916),
    "m_furn_basin": ("water（卫浴小件）", 0.360, 0.557, 0.453, 4500),
    "m_furn_sofa_cherry": ("樱桃沙发", 0.600, 1.600, 0.700, 460),
    "m_furn_sofa_cushion": ("抱枕沙发", 1.597, 0.722, 0.767, 4500),
    "m_furn_coffee_table": ("茶几", 1.001, 0.701, 0.440, 656),
    "m_furn_sofa_large": ("大沙发", 2.364, 0.766, 0.751, 4500),
    "m_furn_chest_tall": ("高柜", 1.000, 0.500, 2.400, 836),
    "m_furn_table_round": ("圆桌", 0.959, 0.950, 0.751, 3628),
    "m_furn_armchair": ("单人沙发椅", 1.011, 0.771, 0.750, 4500),
    "m_furn_table_low": ("矮桌", 0.896, 0.515, 0.379, 288),
}


def plan():
    items = []
    for i, (mid, (_n, w, d, h, _f)) in enumerate(SPECS.items()):
        items.append({
            "id": "i%d" % i, "kind": "asset", "model": mid,
            "x": (i % 6) * 4.0, "y": (i // 6) * 3.2, "rot": 0,
            "sw": w, "sd": d, "sh": h,
        })
    return {"name": "furniture42", "walls": [], "openings": [], "items": items}


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
            pg.wait_for_timeout(2500)

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
                    "min": e.get("min"),
                    "ground_ok": abs((e.get("min") or [0, 0, 0])[1]) < 0.05,
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
                if not row["ground_ok"]:
                    failed.append(f"{mid}: 未落地 min.y={(e.get('min') or [])}")
            out["items"] = rows

            # 3b) 离地高度：awning 1.5m / 落地件 0m
            lift_plan = {"name": "liftprobe", "walls": [], "openings": [],
                         "items": [
                             {"id": "L0", "kind": "asset",
                              "model": "m_courtyard_awning",
                              "x": 0, "y": 0, "rot": 0,
                              "sw": 3.1, "sd": 1.69, "sh": 0.62, "off": 1500},
                             {"id": "L1", "kind": "asset",
                              "model": "m_furn_desk",
                              "x": 8, "y": 0, "rot": 0,
                              "sw": 1.4, "sd": 0.591, "sh": 0.758},
                         ]}
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                        lift_plan)
            pg.wait_for_timeout(900)
            lift = {d["id"]: d for d in pg.evaluate("window.jiajia.debugItems()")}
            a_min = (lift.get("L0", {}).get("min") or [0, 0, 0])[1]
            d_min = (lift.get("L1", {}).get("min") or [0, 0, 0])[1]
            out["lift_probe"] = {"awning_min_y": a_min, "desk_min_y": d_min,
                                 "awning_off_mm": 1500}
            out["assert_lift_awning"] = abs(a_min - 1.5) < 0.05
            out["assert_lift_ground"] = abs(d_min) < 0.05
            if not out["assert_lift_awning"]:
                failed.append(f"awning 离地 {a_min} != 1.5")
            if not out["assert_lift_ground"]:
                failed.append(f"落地件 min.y {d_min} != 0")

            # 4) models_ext.js 缺席 → 占位盒 + 不崩
            pg.evaluate("window.JJ_EXT_MODELS = undefined")
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))", plan())
            pg.wait_for_timeout(1200)
            dbg2 = pg.evaluate("window.jiajia.debugItems()")
            out["missing_ext_count"] = len(dbg2)
            out["assert_missing_ext_placeholder"] = bool(
                len(dbg2) == len(SPECS)
                and all(d["placeholder"] and d["label"] for d in dbg2))

            if args.shot:
                pg.evaluate("window.JJ_EXT_MODELS = window.__JJ_EXT_BACKUP")
                pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                            plan())
                pg.wait_for_timeout(1200)
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
