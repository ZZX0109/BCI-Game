"""抓取当前宿主目录里各游戏的实时 GUI 截图到 screenshots/v_latest/。

要点：
- 用真实 GUI 模式启动 Neuralife（不带 --game-smoke，否则离屏无画面）
- 按子进程 PID 定位窗口，避免标题不确定导致的误匹配
- 用 mss 抓取窗口在屏幕上的合成区域（对 Qt/RHI/GPU 窗口最可靠）
- 每款抓完即关闭，再抓下一款，互不干扰

用法：
    python tools/capture_shots.py
（也可由 run_capture.bat 双击调用，确保GUI子进程不被工具会话清理）
"""
from __future__ import annotations

import os
import subprocess
import sys
import time

import mss
import win32con
import win32gui

EXE = r"D:\program\AIT\Neuralife\bin\Neuralife.exe"
HOST = r"C:\Users\Ait\AppData\Local\AIT\Neuralife\modules\games"
OUT = r"C:\Users\Ait\Desktop\Neuralife\screenshots\v_latest"
DATA_ROOT = r"C:\Users\Ait\AppData\Local\AIT\Neuralife\shotdata"

# 3D 游戏需要 RHI 后端才能渲染；2D 用宿主默认后端
RHI_GAMES = {"luban", "rhythm"}

GAMES = [
    "hanoi", "pursuit", "sokoban", "target",
    "claw", "traffic", "luban", "rhythm",
]

WAIT_WINDOW = 25.0      # 等待窗口出现
WAIT_RENDER = 4.0       # 窗口出现后等渲染稳定
POLL = 0.25


def find_window(pid: int):
    """返回该 pid 下最大的可见窗口句柄与矩形。"""
    best = None

    def enum(hwnd, _):
        nonlocal best
        if not win32gui.IsWindowVisible(hwnd):
            return
        try:
            _, wp = win32gui.GetWindowThreadProcessId(hwnd)
        except Exception:
            return
        if wp != pid:
            return
        title = win32gui.GetWindowText(hwnd)
        left, top, right, bottom = win32gui.GetWindowRect(hwnd)
        w = right - left
        h = bottom - top
        if w < 50 or h < 50:
            return
        score = w * h
        if best is None or score > best[2]:
            best = (hwnd, (left, top, right, bottom), score)

    win32gui.EnumWindows(enum, None)
    return best


def capture_game(gid: str) -> str:
    env = dict(os.environ)
    if gid in RHI_GAMES:
        env["QT_QUICK_BACKEND"] = "rhi"
    data = os.path.join(DATA_ROOT, gid)
    os.makedirs(data, exist_ok=True)

    proc = subprocess.Popen(
        [EXE, "--game-dev", gid, "--games-dev-root", HOST,
         "--game-data-root", data],
        env=env,
    )
    pid = proc.pid
    print(f"  [{gid}] launched pid={pid}", flush=True)

    # 等待窗口
    t0 = time.time()
    box = None
    while time.time() - t0 < WAIT_WINDOW:
        r = find_window(pid)
        if r:
            box = r[1]
            break
        time.sleep(POLL)
    if not box:
        proc.terminate()
        return f"[{gid}] 窗口未出现（超时 {WAIT_WINDOW}s）"

    time.sleep(WAIT_RENDER)

    left, top, right, bottom = box
    path = os.path.join(OUT, f"{gid}.png")
    try:
        with mss.mss() as sct:
            img = sct.grab({"left": left, "top": top,
                            "width": right - left, "height": bottom - top})
            mss.tools.to_png(img.rgb, img.size, output=path)
    except Exception as e:
        proc.terminate()
        return f"[{gid}] 抓图失败: {e}"

    # 关闭窗口
    try:
        win32gui.PostMessage(box[0], win32con.WM_CLOSE, 0, 0)
    except Exception:
        pass
    try:
        proc.wait(timeout=8)
    except Exception:
        proc.terminate()

    size = os.path.getsize(path)
    print(f"  [{gid}] saved {path} ({size} bytes, {right-left}x{bottom-top})", flush=True)
    if size < 1500:
        return f"[{gid}] 疑似空白图（{size} bytes）"
    return f"[{gid}] OK"


def main():
    os.makedirs(OUT, exist_ok=True)
    order = GAMES
    if len(sys.argv) > 1:
        order = [g for g in GAMES if g in sys.argv[1:]]
    summary = []
    for gid in order:
        print(f">> {gid}", flush=True)
        try:
            res = capture_game(gid)
        except Exception as e:
            res = f"[{gid}] 异常: {e}"
        summary.append(res)
        time.sleep(1.0)
    print("\n==== 结果 ====")
    for s in summary:
        print(s)


if __name__ == "__main__":
    sys.exit(main())
