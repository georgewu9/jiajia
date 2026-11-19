#!/usr/bin/env python3
"""v0.1.35 F1 回归探针：开洞（窗）上方过梁 / 台下实墙 / 两侧墙段是否成片。

背景：v0.1.34 洞口挂 CC0 实模（Opening.m）后，`buildWalls` 的 window 分支只画了
窗台下实墙 + 实模，洞口顶（sill+洞高）→ 墙顶的过梁段整段丢失，3D 里墙上出现
一个方形缺口（用户截图）。修法见 assets/web/viewer.js window 分支。

探针（无头 Chromium + 本地 http.server，套路同 scratch/lib3d_check.py）：
  1) 2.8m 高墙 + 窗洞（sill 0.9 / 洞高 1.3）挂 modelId='m_window_deep'
  2) 同形不含 m 的对照用例
两组都断言：
  - 墙面切片 yMax >= 2.79（墙体到顶）
  - 过梁区（x∈洞宽内, y∈2.3..2.7, z=墙中线）射线命中墙体
  - 台下区（y∈0..0.9）射线命中墙体
  - 洞口左右两侧（洞外 0.7m）射线命中墙体实段
  - 挂 m 时洞内是 OBJ 实模（debugExtOpenings 高≈洞高、通用玻璃不存在）；
    对照用例洞内是通用玻璃
  3) F2 顺带校验：入户大门规格 910×2100（m_frontDoorDark）在 910×2100 洞口内
     世界尺寸 ≈ 0.91×2.10，且洞口顶→墙顶同样有过梁。

用法：python3 tool/open_slice_check.py [--shot out.png]
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
PORT = 8137


def window_plan(with_model: bool) -> dict:
    """2.8m 墙 + 窗洞：sill 0.9m、洞高 1.3m（洞口顶 2.2m）。"""
    o = {"id": "o1", "wall": "w1", "kind": "window", "dt": "single",
         "off": 2.0, "w": 1.2, "sill": 0.9, "ht": 1.3,
         "out": False, "hl": True}
    if with_model:
        o["m"] = "m_window_deep"
    return {
        "name": "openslice_win" + ("_ext" if with_model else "_plain"),
        "walls": [{"id": "w1", "ax": 0, "ay": 0, "bx": 6, "by": 0,
                   "t": 0.24, "h": 2.8}],
        "openings": [o],
        "items": [],
    }


def door_plan() -> dict:
    """F2：入户大门 910×2100 开洞（洞顶 2.1m），墙高 2.8m。"""
    return {
        "name": "openslice_door",
        "walls": [{"id": "w1", "ax": 0, "ay": 0, "bx": 6, "by": 0,
                   "t": 0.24, "h": 2.8}],
        "openings": [{"id": "d1", "wall": "w1", "kind": "door",
                      "dt": "single", "off": 2.0, "w": 0.91,
                      "sill": 0.0, "ht": 2.1, "out": False, "hl": True,
                      "m": "m_frontDoorDark"}],
        "items": [],
    }


OPEN_MIN_X, OPEN_MAX_X = 2.0, 3.2      # 窗洞 x 区段（off..off+w）


def probes(pg, xs, ys):
    """在 (x, y, z=0) 沿 +z 打墙切片射线，返回命中矩阵。"""
    out = []
    for x in xs:
        for y in ys:
            out.append({"x": x, "y": y,
                        "hit": pg.evaluate(
                            "([x,y]) => window.jiajia.debugWallProbe(x,y,0)",
                            [x, y])})
    return out


def all_hit(rows):
    return all(r["hit"]["hit"] for r in rows)


def run(pg, plan, tag, out, need_below=True):
    pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))", plan)
    pg.wait_for_timeout(500)
    slices = pg.evaluate("window.jiajia.debugWallSlices()")
    ext = pg.evaluate("window.jiajia.debugExtOpenings()")
    win = pg.evaluate("window.jiajia.debugOpenings()")["windows"]

    ymax = max(s["max"][1] for s in slices) if slices else 0
    roles = sorted({s["role"] for s in slices})
    lintel_rows = probes(pg, [2.3, 2.6, 3.1], [2.25, 2.4, 2.6, 2.75])
    below_rows = probes(pg, [2.3, 2.6, 3.1], [0.1, 0.45, 0.85])
    side_rows = probes(pg, [1.0, 4.4], [1.4])
    want = {"solid", "lintel"} | ({"below"} if need_below else set())

    res = {
        "tag": tag,
        "slices": slices,
        "roles": roles,
        "wall_ymax": round(ymax, 3),
        "assert_wall_to_top": ymax >= 2.79,
        "assert_roles_complete": want <= set(roles),
        "lintel_samples": lintel_rows,
        "assert_lintel_covered": all_hit(lintel_rows),
        "below_samples": below_rows,
        "assert_below_covered": all_hit(below_rows) if need_below else None,
        "side_samples": side_rows,
        "assert_sides_covered": all_hit(side_rows),
        "ext_openings": ext,
        "generic_glass_count": len(win),
    }
    out[tag] = res


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
                " window.jiajia.debugWallProbe)")

            run(pg, window_plan(True), "window_with_model", out)
            run(pg, window_plan(False), "window_plain_control", out)
            run(pg, door_plan(), "door_f2_spec", out, need_below=False)

            # 挂 m 的窗：洞内必须是实模（高≈洞高 1.3、宽≈洞宽 1.2），无通用玻璃
            wm = out["window_with_model"]
            e = wm["ext_openings"][0] if wm["ext_openings"] else None
            wm["assert_ext_model_in_hole"] = bool(
                e and abs(e["size"][0] - 1.2) < 0.03
                and abs(e["size"][1] - 1.3) < 0.03
                and len(wm["ext_openings"]) == 1)
            wm["assert_no_generic_glass"] = wm["generic_glass_count"] == 0
            # 对照：同样形状不挂 m → 通用玻璃在位、无实模
            wp = out["window_plain_control"]
            wp["assert_generic_glass"] = wp["generic_glass_count"] == 1
            wp["assert_no_ext_model"] = len(wp["ext_openings"]) == 0
            # F2：入户大门 910×2100 实模世界尺寸 + 门顶过梁
            df = out["door_f2_spec"]
            de = df["ext_openings"][0] if df["ext_openings"] else None
            df["assert_door_spec_910x2100"] = bool(
                de and abs(de["size"][0] - 0.91) < 0.03
                and abs(de["size"][1] - 2.10) < 0.03)
            df["lintel_samples"] = probes(pg, [2.2, 2.4, 2.6],
                                          [2.15, 2.4, 2.75])
            df["assert_lintel_covered"] = all_hit(df["lintel_samples"])

            if args.shot:
                pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                            window_plan(True))
                pg.wait_for_timeout(400)
                pg.evaluate("window.jiajia.setMode('orbit')")
                pg.wait_for_timeout(400)
                pg.screenshot(path=args.shot)
                out["screenshot"] = args.shot
            b.close()
    finally:
        srv.terminate()

    out["pageerrors"] = errs
    out["assert_no_pageerror"] = len(errs) == 0
    failed = []
    for tag in ("window_with_model", "window_plain_control", "door_f2_spec"):
        for k, v in out[tag].items():
            if k.startswith("assert_") and v is False:
                failed.append(f"{tag}.{k}")
    if not out["assert_no_pageerror"]:
        failed.append("pageerror")
    out["failed"] = failed
    out["ok"] = not failed
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
