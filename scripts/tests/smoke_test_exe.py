import subprocess
import time
import sys
import os
import pyautogui
import pygetwindow as gw
import win32gui
import win32con
from PIL import Image

# 禁用 pyautogui 的安全特性
pyautogui.FAILSAFE = False

EXE_PATH = r"C:\Users\wanzh\Desktop\Intuita\build\Intuita.exe"
LOG_PATH = r"C:\Users\wanzh\Desktop\Intuita\build\smoke_test.log"
SHOT_DIR = r"C:\Users\wanzh\Desktop\Intuita\build\smoke_shots"


def main():
    os.makedirs(SHOT_DIR, exist_ok=True)

    print(f"[烟雾测试] 启动 {EXE_PATH}")
    with open(LOG_PATH, "w", encoding="utf-8") as log_file:
        proc = subprocess.Popen(
            [EXE_PATH],
            stdout=log_file,
            stderr=subprocess.STDOUT,
            cwd=os.path.dirname(EXE_PATH),
        )

        try:
            # 等待窗口出现
            hwnd = wait_for_window("Intuita", timeout=15)
            if hwnd == 0:
                print("[烟雾测试] 错误：未找到 Intuita 窗口")
                return

            activate_and_topmost(hwnd)
            time.sleep(1)

            # 截取主菜单
            shot_main = capture_window(hwnd, os.path.join(SHOT_DIR, "01_main_menu.png"))
            print(f"[烟雾测试] 主菜单截图: {shot_main}")

            # 获取窗口中心，点击战役按钮（按钮在卡片上部，中心偏上约100像素）
            rect = win32gui.GetClientRect(hwnd)
            cx = rect[2] // 2
            cy = rect[3] // 2
            center_pos = win32gui.ClientToScreen(hwnd, (cx, cy))
            campaign_pos = win32gui.ClientToScreen(hwnd, (cx, cy - 100))
            print(f"[烟雾测试] 点击战役模式按钮 {campaign_pos}")
            pyautogui.click(campaign_pos[0], campaign_pos[1])

            time.sleep(5)
            activate_and_topmost(hwnd)

            # 截取游戏场景
            shot_game = capture_window(hwnd, os.path.join(SHOT_DIR, "02_game_scene.png"))
            print(f"[烟雾测试] 游戏场景截图: {shot_game}")

            # 点击游戏中心放置原子
            print(f"[烟雾测试] 点击游戏中心放置原子 {center_pos}")
            pyautogui.click(center_pos[0], center_pos[1])
            time.sleep(0.5)
            pyautogui.click(center_pos[0], center_pos[1])
            time.sleep(2)
            activate_and_topmost(hwnd)

            shot_after = capture_window(hwnd, os.path.join(SHOT_DIR, "03_after_click.png"))
            print(f"[烟雾测试] 点击后截图: {shot_after}")

            # 检测画面变化
            diff = compare_images(shot_game, shot_after)
            print(f"[烟雾测试] 游戏画面变化像素数: {diff}")

            # 读取日志
            proc.poll()
            log_file.flush()
            with open(LOG_PATH, "r", encoding="utf-8", errors="ignore") as f:
                log_text = f.read()

            has_place_log = (
                "放置" in log_text
                or "atom" in log_text.lower()
                or "构造" in log_text
                or "Wyckoff" in log_text
            )
            print(f"[烟雾测试] 日志中检测到放置相关记录: {has_place_log}")

            if diff > 500:
                print("[烟雾测试] 结果: PASS - 检测到画面变化")
            else:
                print("[烟雾测试] 结果: UNCERTAIN - 画面变化不明显")

        finally:
            print("[烟雾测试] 结束进程")
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


def wait_for_window(title: str, timeout: int = 15) -> int:
    start = time.time()
    while time.time() - start < timeout:
        hwnd = win32gui.FindWindow(None, title)
        if hwnd != 0:
            return hwnd
        time.sleep(0.5)
    return 0


def activate_and_topmost(hwnd: int) -> None:
    win32gui.ShowWindow(hwnd, win32con.SW_RESTORE)
    try:
        win32gui.SetForegroundWindow(hwnd)
    except Exception:
        pass
    # 置顶
    win32gui.SetWindowPos(
        hwnd,
        win32con.HWND_TOPMOST,
        0, 0, 0, 0,
        win32con.SWP_NOMOVE | win32con.SWP_NOSIZE | win32con.SWP_SHOWWINDOW,
    )
    time.sleep(0.2)


def capture_window(hwnd: int, save_path: str) -> str:
    # 获取客户区位置
    rect = win32gui.GetClientRect(hwnd)
    left, top = win32gui.ClientToScreen(hwnd, (rect[0], rect[1]))
    right, bottom = win32gui.ClientToScreen(hwnd, (rect[2], rect[3]))
    img = pyautogui.screenshot(region=(left, top, right - left, bottom - top))
    img.save(save_path)
    return save_path


def compare_images(path_a: str, path_b: str) -> int:
    try:
        img_a = Image.open(path_a).convert("RGB")
        img_b = Image.open(path_b).convert("RGB")
        if img_a.size != img_b.size:
            return -1
        pixels_a = img_a.load()
        pixels_b = img_b.load()
        diff = 0
        for y in range(img_a.height):
            for x in range(img_a.width):
                if pixels_a[x, y] != pixels_b[x, y]:
                    diff += 1
        return diff
    except Exception as e:
        print(f"[烟雾测试] 比较截图失败: {e}")
        return -1


if __name__ == "__main__":
    main()
