#!/usr/bin/env python3
"""v0.1.39 第一视角碰撞探针：门洞可通行、只挡墙（无头 Chromium + 本地 http.server，
套路同 tool/courtyard_check.py / tool/open_slice_check.py）。

背景：viewer.js buildWalls() 旧实现把整条墙线推进 wallAABB（不看 plan.openings），
渲染层却按开洞切段 → 门洞在 3D 里是空的，碰撞层仍是实心墙，第一视角走到门洞
被「隐形墙」挡住。

验证（单向长墙：a=(-3,0) → b=(3,0)，t=0.24 → r = t/2+0.35 = 0.47）：
  门洞  off=2.55 w=0.90 → 洞口 x∈[-0.45,0.45]
  窗    off=0.40 w=1.20 → 洞口 x∈[-2.60,-1.40]（sill 0.9 / ht 1.5）
  1) 直闯门洞（x=0，从 z=+1.6 向 -z）→ 穿过墙线（z < -0.8），x 仍在洞口中心 ±0.3
  2) 直闯实墙段（x=1.5）→ 被挡在墙外，|z - 0.47| < 0.1
  3) 直闯窗段（x=-2.0）→ 同样被挡（窗户不可穿）
  4) 回归：无 openings 的旧计划 → 整墙照旧可挡（|z - 0.47| < 0.1）
  另加结构断言：碰撞表里没有覆盖门洞内部的线段、窗段按实墙登记。

驱动方式（最小侵入）：setMode('first') → debugPlace(x,z,π)（yaw=π 时主循环的
前进方向 = -z）→ 在 #dp-up 上派发 pointerdown「按住」，主循环照常每帧推进
（speed = 1.8 m/s，逐帧 collide() 夹紧），采样 uiState().pos。

用法：python3 tool/firstperson_check.py
退出码 0 = 全部通过；1 = 有断言失败（明细打到 stdout 的 JSON）。
"""
import json
import os
import subprocess
import sys
import time

ROOT = os.environ.get(
    "JJ_WEB_ROOT",
    os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                 "assets", "web"))
PORT = 8141

TH = 0.24
R = TH / 2 + 0.35          # 0.47：碰撞半径（viewer.js buildWalls 里的表达式）
DOOR = {"c": 0.0, "w": 0.90}
WIN = {"c": -2.00, "w": 1.20}
DOOR_SPAN = (DOOR["c"] - DOOR["w"] / 2, DOOR["c"] + DOOR["w"] / 2)
WIN_SPAN = (WIN["c"] - WIN["w"] / 2, WIN["c"] + WIN["w"] / 2)


def wall():
    return {"id": "w1", "ax": -3.0, "ay": 0.0, "bx": 3.0, "by": 0.0,
            "t": TH, "h": 2.8}


def plan_with_openings():
    """横墙 + 门洞（中偏右）+ 窗户（左侧）。"""
    off = lambda c, w: (c + 3.0) - w / 2   # 墙 a 在 x=-3 → off 从 a 量起
    return {
        "name": "fp_collision", "walls": [wall()], "items": [],
        "openings": [
            {"id": "o1", "wall": "w1", "kind": "door", "dt": "doorway",
             "off": off(DOOR["c"], DOOR["w"]), "w": DOOR["w"],
             "sill": 0, "ht": 2.0},
            {"id": "o2", "wall": "w1", "kind": "window", "dt": "single",
             "off": off(WIN["c"], WIN["w"]), "w": WIN["w"],
             "sill": 0.9, "ht": 1.5},
        ],
    }


def plan_plain():
    """旧计划：同一面墙，没有任何开洞（回归：整墙整条挡人）。"""
    return {"name": "fp_plain", "walls": [wall()], "items": [], "openings": []}


HOLD_DOWN = """() => { const b = document.getElementById('dp-up');
  b.dispatchEvent(new PointerEvent('pointerdown',
    { bubbles: true, pointerId: 1, isPrimary: true })); }"""
HOLD_UP = """() => { const b = document.getElementById('dp-up');
  b.dispatchEvent(new PointerEvent('pointerup',
    { bubbles: true, pointerId: 1, isPrimary: true })); }"""


def drive(pg, x, z, seconds=3.0, samples=12):
    """把玩家放到 (x,z) 面向 -z，按住「上」跑 seconds 秒，返回采样轨迹。"""
    pg.evaluate("window.jiajia.setMode('first')")
    pg.evaluate("(p) => window.jiajia.debugPlace(p[0], p[1], Math.PI)",
                [x, z])
    pg.evaluate(HOLD_DOWN)
    trail = []
    for _ in range(samples):
        pg.wait_for_timeout(int(seconds * 1000 / samples))
        trail.append(pg.evaluate("window.jiajia.uiState()"))
    pg.evaluate(HOLD_UP)
    pg.wait_for_timeout(120)
    trail.append(pg.evaluate("window.jiajia.uiState()"))
    return trail


def main():
    from playwright.sync_api import sync_playwright

    srv = subprocess.Popen([sys.executable, "-m", "http.server", str(PORT),
                            "-d", ROOT],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    out, errs, failed = {}, [], []
    try:
        with sync_playwright() as p:
            b = p.chromium.launch(args=[
                "--enable-unsafe-swiftshader",
                "--disable-background-timer-throttling",
                "--disable-renderer-backgrounding",
            ])
            pg = b.new_page(viewport={"width": 1000, "height": 700},
                            device_scale_factor=1)
            pg.on("pageerror", lambda e: errs.append(str(e)))
            pg.goto(f"http://127.0.0.1:{PORT}/viewer.html")
            pg.wait_for_function(
                "() => !!(window.jiajia && window.jiajia.setPlan &&"
                " window.jiajia.debugPlace && window.jiajia.uiState)")

            # ---------- 计划：墙 + 门洞 + 窗 ----------
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                        plan_with_openings())
            pg.wait_for_timeout(400)

            segs = pg.evaluate("window.jiajia.debugWallAABB()")
            out["segments_door_plan"] = segs
            # 结构断言：门洞内部不得有碰撞线段（线段须整段落在洞口左或右）
            covers_door = []
            for s in segs:
                if s["ay"] == 0 and s["by"] == 0:
                    lo, hi = min(s["ax"], s["bx"]), max(s["ax"], s["bx"])
                    if hi > DOOR_SPAN[0] + 0.01 and lo < DOOR_SPAN[1] - 0.01:
                        covers_door.append(s)
            out["assert_no_collision_across_door"] = not covers_door
            if covers_door:
                failed.append("碰撞表仍有线段横跨门洞: %s" % covers_door)
            # 结构断言：窗段按实墙登记（存在一条与窗洞同跨的线段）
            win_seg = [s for s in segs if s["ay"] == 0 and s["by"] == 0
                       and abs(min(s["ax"], s["bx"]) - WIN_SPAN[0]) < 0.01
                       and abs(max(s["ax"], s["bx"]) - WIN_SPAN[1]) < 0.01]
            out["assert_window_has_collision"] = bool(len(win_seg) == 1)
            if not win_seg:
                failed.append("窗段没有碰撞线段（窗应不可穿）")
            out["assert_segment_count"] = len(segs)
            # solid×3（左、门左、门右之后）+ 窗×1 = 4
            out["assert_segment_count_ok"] = len(segs) == 4
            if len(segs) != 4:
                failed.append("碰撞线段数 %d != 4（solid×3 + 窗×1）" % len(segs))

            # ---------- a) 直闯门洞 ----------
            tr = drive(pg, DOOR["c"], 1.6, seconds=3.0)
            door = {"trail": [[t["pos"][0], t["pos"][1]] for t in tr],
                    "final": tr[-1]["pos"]}
            door["crossed"] = door["final"][1] < -0.8
            door["x_err"] = abs(door["final"][0] - DOOR["c"])
            door["x_ok"] = door["x_err"] < 0.3
            door["ok"] = door["crossed"] and door["x_ok"]
            out["door"] = door
            if not door["ok"]:
                failed.append("门洞不可通行: final=%s (crossed=%s x_err=%.3f)"
                              % (door["final"], door["crossed"], door["x_err"]))

            # ---------- b) 直闯实墙段 ----------
            tr = drive(pg, 1.5, 1.6, seconds=2.0)
            solid = {"trail": [[t["pos"][0], t["pos"][1]] for t in tr],
                     "final": tr[-1]["pos"]}
            solid["dist"] = abs(solid["final"][1])
            solid["dist_err"] = abs(solid["dist"] - R)
            solid["ok"] = solid["dist_err"] < 0.1 and solid["final"][1] > 0
            out["solid"] = solid
            if not solid["ok"]:
                failed.append("实墙段没挡住: final=%s dist_err=%.3f"
                              % (solid["final"], solid["dist_err"]))

            # ---------- c) 直闯窗段 ----------
            tr = drive(pg, WIN["c"], 1.6, seconds=2.0)
            win = {"trail": [[t["pos"][0], t["pos"][1]] for t in tr],
                   "final": tr[-1]["pos"]}
            win["dist"] = abs(win["final"][1])
            win["dist_err"] = abs(win["dist"] - R)
            win["ok"] = win["dist_err"] < 0.1 and win["final"][1] > 0
            out["window"] = win
            if not win["ok"]:
                failed.append("窗段没挡住（窗不可穿）: final=%s dist_err=%.3f"
                              % (win["final"], win["dist_err"]))

            # ---------- d) 回归：无门洞旧计划 ----------
            pg.evaluate("pl => window.jiajia.setPlan(JSON.stringify(pl))",
                        plan_plain())
            pg.wait_for_timeout(400)
            segs0 = pg.evaluate("window.jiajia.debugWallAABB()")
            tr = drive(pg, 0.5, 1.6, seconds=2.0)
            reg = {"trail": [[t["pos"][0], t["pos"][1]] for t in tr],
                   "final": tr[-1]["pos"], "segments": segs0}
            reg["dist"] = abs(reg["final"][1])
            reg["dist_err"] = abs(reg["dist"] - R)
            reg["one_full_segment"] = (len(segs0) == 1
                                       and abs(segs0[0]["ax"] + 3.0) < 0.001
                                       and abs(segs0[0]["bx"] - 3.0) < 0.001)
            reg["ok"] = (reg["dist_err"] < 0.1 and reg["final"][1] > 0
                         and reg["one_full_segment"])
            out["regression_plain"] = reg
            if not reg["ok"]:
                failed.append("旧计划（无开洞）整墙未挡住: final=%s segs=%s"
                              % (reg["final"], segs0))
            b.close()
    finally:
        srv.terminate()

    out["pageerrors"] = errs
    out["assert_no_pageerror"] = len(errs) == 0
    if errs:
        failed.append("pageerror")
    out["failed"] = failed
    out["ok"] = not failed
    print(json.dumps(out, ensure_ascii=False, indent=1))
    return 0 if out["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
