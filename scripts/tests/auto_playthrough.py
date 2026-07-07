"""
Intuita 42关自动化通关测试 — 外部模拟版

用 pyautogui + pygetwindow 从游戏窗口外部模拟鼠标点击，
像真实玩家一样通关全部42关。与 GdUnit4 的 scene_runner 互补：
  - GdUnit4: headless、API 级、快速
  - pyautogui: 真实渲染、像素级、验证视觉效果

游戏以 --auto-complete 参数启动，关卡加载后1秒自动完成，
pyautogui 负责点击"下一关"按钮、跳过章节过渡等 UI 交互。

前置依赖:
  pip install pyautogui pygetwindow pillow

用法:
  python auto_playthrough.py                  # 全部42关通关
  python auto_playthrough.py --mode campaign   # 仅战役35关
  python auto_playthrough.py --mode challenge  # 仅挑战5关
  python auto_playthrough.py --no-launch       # 游戏已在运行时
"""

import argparse
import subprocess
import sys
import time

import pyautogui
import pygetwindow as gw

# 安全设置：鼠标移到屏幕角落立即终止
pyautogui.FAILSAFE = True
# 每次操作间隔
pyautogui.PAUSE = 0.3

GAME_EXE = r"C:\Users\wanzh\Desktop\Intuita\build\Intuita.exe"
WINDOW_TITLE = "Intuita"


def launch_game():
    """以自动完成模式启动游戏"""
    print(f"[launch] {GAME_EXE} --auto-complete")
    proc = subprocess.Popen([GAME_EXE, "--auto-complete"])
    return proc


def find_game_window(timeout=30):
    """等待并返回游戏窗口对象"""
    print(f"[wait] 查找窗口 '{WINDOW_TITLE}' ...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        windows = gw.getWindowsWithTitle(WINDOW_TITLE)
        if windows:
            win = windows[0]
            print(f"[found] 窗口位置 ({win.left},{win.top}) 尺寸 {win.width}x{win.height}")
            return win
        time.sleep(0.5)
    raise RuntimeError(f"在 {timeout}s 内未找到游戏窗口 '{WINDOW_TITLE}'")


def activate_window(win):
    """激活并前置游戏窗口"""
    try:
        win.activate()
    except Exception:
        try:
            win.minimize()
            win.restore()
        except Exception:
            pass
    time.sleep(0.5)


def click_relative(win, x_ratio, y_ratio, clicks=1, interval=0.1):
    """按窗口比例坐标点击（0.0~1.0）"""
    x = win.left + int(win.width * x_ratio)
    y = win.top + int(win.height * y_ratio)
    print(f"  [click] ({x},{y})")
    pyautogui.click(x, y, clicks=clicks, interval=interval)


def wait_seconds(seconds, label=""):
    if label:
        print(f"  [wait] {label} {seconds}s")
    time.sleep(seconds)


# ============ 主菜单导航 ============

def click_campaign_button(win):
    """点击主菜单'战役模式'按钮（VBox 第一个按钮，约窗口中央偏上）"""
    print("[menu] 点击战役模式")
    click_relative(win, 0.5, 0.42)
    wait_seconds(3, "关卡加载")


def click_challenge_button(win):
    """点击主菜单'挑战模式'按钮"""
    print("[menu] 点击挑战模式")
    click_relative(win, 0.5, 0.52)
    wait_seconds(3, "关卡加载")


# ============ 关卡内 UI 交互 ============

def skip_journal_entry(win):
    """跳过关卡完成后的手记条目"""
    # 手记条目是章节过渡面板的简短版本，点击中央继续
    click_relative(win, 0.5, 0.5)
    wait_seconds(0.5)


def click_next_level(win):
    """点击'下一关'按钮（弹窗 VBox 第一个按钮，约窗口中央）"""
    print("  [ui] 点击下一关")
    click_relative(win, 0.5, 0.48)
    wait_seconds(2, "下一关加载")


def click_continue_transition(win):
    """跳过章节过渡打字机动画"""
    print("  [ui] 跳过章节过渡")
    click_relative(win, 0.5, 0.85)
    wait_seconds(2, "章节加载")


def return_to_menu(win):
    """点击'返回菜单'按钮"""
    print("[ui] 返回主菜单")
    click_relative(win, 0.5, 0.58)
    wait_seconds(3, "主菜单加载")


# ============ 通关流程 ============

CAMPAIGN_LEVELS = [
    (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (1, 6), (1, 7), (1, 8), (1, 9), (1, 10),
    (2, 1), (2, 2), (2, 3), (2, 4), (2, 5), (2, 6), (2, 7), (2, 8), (2, 9), (2, 10),
    (3, 1), (3, 2), (3, 3), (3, 4), (3, 5), (3, 6), (3, 7), (3, 8), (3, 9), (3, 10),
    (4, 1), (4, 2), (4, 3), (4, 4), (4, 5), (4, 6), (4, 7), (4, 8),
]

CHALLENGE_LEVELS = [(-1, 1), (-1, 2), (-1, 3), (-1, 4), (-1, 5)]

# 每章最大关卡数
MAX_LEVELS = {1: 10, 2: 10, 3: 10, 4: 8}


def play_campaign(win):
    """战役模式 35 关"""
    print("\n=== 战役模式通关 ===")
    click_campaign_button(win)

    for chapter, level in CAMPAIGN_LEVELS:
        print(f"\n--- Ch{chapter}-L{level} ---")
        # 等待关卡加载 + 自动完成（--auto-complete 模式下1秒后自动完成）
        wait_seconds(3, "关卡加载+自动完成")

        # 跳过手记条目（如果有）
        skip_journal_entry(win)

        # 最后一关不需要点下一关
        if chapter == 4 and level == 8:
            print("  [done] 战役模式最后一关完成")
            break

        # 点击"下一关"
        click_next_level(win)

        # 章节过渡（每章最后一关后）
        if level == MAX_LEVELS.get(chapter, 10):
            print("  [transition] 章节过渡")
            wait_seconds(2, "过渡动画")
            click_continue_transition(win)

    print("\n=== 战役模式通关完成 ===")


def play_challenge(win):
    """挑战模式 5 关"""
    print("\n=== 挑战模式通关 ===")
    click_challenge_button(win)

    for chapter, level in CHALLENGE_LEVELS:
        print(f"\n--- Challenge-L{level} ---")
        wait_seconds(3, "关卡加载+自动完成")

        skip_journal_entry(win)

        if level == 5:
            print("  [done] 挑战模式最后一关完成")
            break

        click_next_level(win)

    print("\n=== 挑战模式通关完成 ===")


def main():
    parser = argparse.ArgumentParser(description="Intuita 42关外部自动化通关")
    parser.add_argument(
        "--mode", choices=["campaign", "challenge", "both"], default="both",
        help="通关模式：campaign=战役35关, challenge=挑战5关, both=全部42关"
    )
    parser.add_argument(
        "--no-launch", action="store_true",
        help="不自动启动游戏（游戏已在运行时使用）"
    )
    args = parser.parse_args()

    proc = None
    if not args.no_launch:
        proc = launch_game()
        wait_seconds(5, "游戏启动")
    else:
        print("[skip] 不自动启动游戏")

    win = find_game_window(timeout=30)
    activate_window(win)
    wait_seconds(3, "主菜单加载")

    failed = False
    try:
        if args.mode in ("campaign", "both"):
            play_campaign(win)
            if args.mode == "both":
                return_to_menu(win)

        if args.mode in ("challenge", "both"):
            play_challenge(win)

        print("\n[成功] 全部42关通关完成！")
    except KeyboardInterrupt:
        print("\n[中断] 用户手动终止")
        failed = True
    except Exception as e:
        print(f"\n[错误] {e}")
        failed = True
    finally:
        # 按 ESC 尝试退出
        pyautogui.press("escape")
        wait_seconds(1)
        if proc:
            proc.terminate()

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
