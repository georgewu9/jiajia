#!/usr/bin/env python3
"""v0.1.49 梁 / 地台「离地高度」3D 回归探针（无头 Chromium + 本地 http.server，
套路同 tool/furniture_check.py）。

断言（viewer.js L950-956 通用方盒分支应用 off/el 抬高）：
  1) 梁 off=2400 → bbox 底面 y ≈ 2.400m，size ≈ [2.4, 0.35, 0.30]
  2) 梁无 off（旧数据）→ 底面 y ≈ 0（落地，不崩）
  3) 地台默认（无 off）→ 底面 y ≈ 0，size ≈ [1.5, 0.15, 1.2]
  4) 地台 off=150 → 底面 y ≈ 0.150
  5) 回归：沙发（程序化分支）仍落地 y ≈ 0
  6) 敏感性验证：把 viewer.js 那一行临时改回旧写法（box.position.set(i.x, bh/2, i.y)）
     复跑，梁/地台抬高断言**必须失败**（证明探针真的在测这条改动，而不是恒绿）。
     旧写法只出现在 temp 副本里，仓库文件零改动。

用法：python3 tool/beam_lift_check.py [--shot out.png]
退出码 0 = 正跑全绿 且 敏感性验证成功检出回退；1 = 任一不满足。
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.environ.get(
    "JJ_WEB_ROOT",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "assets", "web"))
PORT = 8141
PORT_STALE = 8142

NEW_LINE = "box.position.set(i.x, (i.el || 0) + liftM + bh / 2, i.y);"
OLD_LINE = "box.position.set(i.x, bh / 2, i.y);"

# 梁 1) off=2400；梁 2) 无 off（旧数据）；地台 3) 默认；地台 4) off=150
# 沙发 5) 程序化分支回归
PLAN = {
    "name": "beamlift", "walls": [], "openings": [],
    "items": [
        {"id": "B1", "kind": "beam", "x": 0.0, "y": 0.0, "rot": 0,
         "off": 2400},
        {"id": "B2", "kind": "beam", "x": 5.0, "y": 0.0, "rot": 0},
        {"id": "P1", "kind": "platform", "x": 0.0, "y": 4.0, "rot": 0},
        {"id": "P2", "kind": "platform", "x": 3.0, "y": 4.0, "rot": 0,
         "off": 150},
        {"id": "S1", "kind": "sofa", "x": 6.5, "y": 4.0, "rot": 0},
    ],
}

# id → (说明, 期望底面 y, 期望 size [x,y,z] 或 None)
CHECKS = {
    "B1": ("梁 off=2400", 2.400, [2.4, 0.35, 0.30]),
    "B2": ("梁无 off（旧数据）", 0.0, [2.4, 0.35, 0.30]),
    "P1": ("地台默认落地", 0.0, [1.5, 0.15, 1.2]),
    "P2": ("地台 off=150", 0.150, [1.5, 0.15, 1.2]),
    "S1": ("沙发（程序化）落地", 0.0, None),
}


def measure(web_root, port, shot=""):
    """起 http.server 跑一次场景，返回 (rows, failed, pageerrors)。"""
    from playwright.sync_api import sync_playwright

    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(port),
                            "-d", web_root],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    rows, failed, errs = [], [], []
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=["--enable-unsafe-swiftshader"])
            pg = b.new_page(viewport={"width": 1000, "height": 700},
                            device_scale_factor=1)
            pg.on("pageerror", lambda e: errs.append(str(e)))
            pg.goto(f"http://127.0.0.1:{port}/viewer.html")
            pg.wait_for_function(
                "() => !!(window.jiajia && window.jiajia.setPlan &&"
                " window.jiajia.debugItems)")
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))", PLAN)
            pg.wait_for_timeout(2000)
            dbg = {d["id"]: d for d in pg.evaluate(
                "window.jiajia.debugItems()")}
            for iid, (name, want_y, want_sz) in CHECKS.items():
                e = dbg.get(iid)
                if not e:
                    failed.append(f"{iid}（{name}）: debugItems 缺条目")
                    continue
                my = (e.get("min") or [0, 0, 0])[1]
                sz = e.get("size") or [0, 0, 0]
                y_ok = abs(my - want_y) <= 0.01
                sz_ok = (want_sz is None or all(
                    abs(a - b2) <= 0.01 for a, b2 in zip(sz, want_sz)))
                rows.append({
                    "id": iid, "what": name, "kind": e.get("kind"),
                    "min_y": my, "want_min_y": round(want_y, 3),
                    "size": sz, "want_size": want_sz,
                    "min_y_ok": y_ok, "size_ok": sz_ok,
                })
                if not y_ok:
                    failed.append(
                        f"{iid}（{name}）: min.y {my} != {want_y}")
                if not sz_ok:
                    failed.append(f"{iid}（{name}）: size {sz} != {want_sz}")
            if shot:
                pg.evaluate("window.jiajia.setMode('orbit')")
                pg.wait_for_timeout(400)
                pg.screenshot(path=shot)
            b.close()
    finally:
        srv.terminate()
        try:
            srv.wait(timeout=5)
        except Exception:
            srv.kill()
    return rows, failed, errs


def make_stale_copy():
    """把 web 根复制到临时目录，并把抬高那一行改回 v0.1.48 旧写法。"""
    tmp = tempfile.mkdtemp(prefix="jj_stale_web_")
    dst = os.path.join(tmp, "web")
    shutil.copytree(ROOT, dst)
    p = os.path.join(dst, "viewer.js")
    src = open(p, encoding="utf-8").read()
    if NEW_LINE not in src:
        raise SystemExit(f"viewer.js 未找到预期抬高行：{NEW_LINE}")
    open(p, "w", encoding="utf-8").write(src.replace(NEW_LINE, OLD_LINE, 1))
    return tmp, dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot", default="")
    args = ap.parse_args()

    out: dict[str, object] = {"probe": "beam_lift_check", "new_line": NEW_LINE}

    # ---- 正跑：仓库当前代码必须全绿 ----
    rows, failed, errs = measure(ROOT, PORT, args.shot)
    out["rows"] = rows
    out["pageerrors"] = errs
    out["failed"] = failed
    out["ok"] = not failed and not errs

    # ---- 敏感性验证：旧写法副本必须被探针检出 ----
    tmp, stale_root = make_stale_copy()
    try:
        s_rows, s_failed, s_errs = measure(stale_root, PORT_STALE)
        s_by = {r["id"]: r for r in s_rows}
        # 旧写法下梁/地台都不抬高：B1 min.y≈0、P2 min.y≈0
        detected = (
            bool(s_failed)
            and s_by.get("B1", {}).get("min_y") is not None
            and abs(s_by["B1"]["min_y"]) <= 0.01
            and abs(s_by.get("P2", {}).get("min_y", -1)) <= 0.01
            and not s_by.get("B1", {}).get("min_y_ok", True)
        )
        out["sensitivity"] = {
            "stale_failed": s_failed,
            "stale_B1_min_y": s_by.get("B1", {}).get("min_y"),
            "stale_P2_min_y": s_by.get("P2", {}).get("min_y"),
            "stale_pageerrors": s_errs,
            "detected": detected,
        }
        if not detected:
            failed.append("敏感性验证失败：旧写法未被探针检出（探针恒绿）")
            out["ok"] = False
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    out["failed"] = failed
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
