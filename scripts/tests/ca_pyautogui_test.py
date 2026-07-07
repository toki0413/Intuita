"""
CA 模式真实玩家操作自动化测试

用 pyautogui 从外部操控游戏窗口，模仿真实玩家验证 Chapter 4 Level 6 (Bays' 4555) 的：
  1. 关卡能正常加载并显示 CA 网格
  2. 鼠标右键拖拽可旋转 3D 视角
  3. 左键点击可切换细胞状态
  4. 空格键可启动/暂停自动演化
  5. N 键可单步演化
  6. 演化过程中画面有可见变化

前置依赖:
  pip install pyautogui pygetwindow pillow

用法:
  python scripts/tests/ca_pyautogui_test.py
"""

import subprocess
import sys
import time
from pathlib import Path

import pyautogui
import pygetwindow as gw
from PIL import Image

pyautogui.FAILSAFE = True
pyautogui.PAUSE = 0.1

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
GAME_EXE = PROJECT_ROOT / "build" / "Intuita.exe"
WINDOW_TITLE = "Intuita"
SHOT_DIR = PROJECT_ROOT / "build" / "ca_autotest_screenshots"


def launch_game():
    """启动游戏并直接加载 CA 测试关卡"""
    cmd = [
        str(GAME_EXE),
        "--ca-test",
    ]
    print(f"[launch] {' '.join(cmd)}")
    proc = subprocess.Popen(cmd, cwd=PROJECT_ROOT)
    return proc


def find_game_window(timeout=60):
    """等待并返回游戏窗口"""
    print(f"[wait] 查找窗口 '{WINDOW_TITLE}' ...")
    deadline = time.time() + timeout
    while time.time() < deadline:
        windows = gw.getWindowsWithTitle(WINDOW_TITLE)
        if windows:
            win = windows[0]
            print(f"[found] 位置 ({win.left},{win.top}) 尺寸 {win.width}x{win.height}")
            return win
        time.sleep(0.5)
    raise RuntimeError(f"在 {timeout}s 内未找到游戏窗口 '{WINDOW_TITLE}'")


def activate_window(win):
    """激活窗口"""
    try:
        win.activate()
    except Exception:
        try:
            win.minimize()
            win.restore()
        except Exception:
            pass
    time.sleep(0.5)


def screenshot(win, name):
    """截取游戏窗口并保存"""
    SHOT_DIR.mkdir(parents=True, exist_ok=True)
    path = SHOT_DIR / f"{name}.png"
    img = pyautogui.screenshot(region=(win.left, win.top, win.width, win.height))
    img.save(path)
    print(f"  [shot] 已保存 {path}")
    return img


def crop_center(img, ratio=0.35):
    """裁剪图片中心区域，聚焦于 CA 网格"""
    w, h = img.size
    cw = int(w * ratio)
    ch = int(h * ratio)
    left = (w - cw) // 2
    top = (h - ch) // 2
    return img.crop((left, top, left + cw, top + ch))


def image_diff_ratio(img_a, img_b):
    """计算两张中心区域的差异比例（简单像素差异）"""
    a = crop_center(img_a)
    b = crop_center(img_b)
    if a.size != b.size:
        b = b.resize(a.size)
    # Pillow >= 10 使用 get_flattened_data 替代 getdata
    pixels_a = list(a.convert("RGB").get_flattened_data())
    pixels_b = list(b.convert("RGB").get_flattened_data())
    diff = sum(
        1 for pa, pb in zip(pixels_a, pixels_b)
        if abs(pa[0] - pb[0]) + abs(pa[1] - pb[1]) + abs(pa[2] - pb[2]) > 30
    )
    total = len(pixels_a) // 3
    return diff / total if total else 0.0


def click_relative(win, x_ratio, y_ratio):
    """按窗口比例点击"""
    x = win.left + int(win.width * x_ratio)
    y = win.top + int(win.height * y_ratio)
    print(f"  [click] ({x_ratio:.2f},{y_ratio:.2f}) -> ({x},{y})")
    pyautogui.click(x, y)


def drag_relative(win, start_ratio, end_ratio, duration=0.5, button="right"):
    """按窗口比例拖拽，模拟玩家旋转视角"""
    x1 = win.left + int(win.width * start_ratio[0])
    y1 = win.top + int(win.height * start_ratio[1])
    x2 = win.left + int(win.width * end_ratio[0])
    y2 = win.top + int(win.height * end_ratio[1])
    print(f"  [drag] {button} ({start_ratio}) -> ({end_ratio})")
    pyautogui.moveTo(x1, y1)
    pyautogui.dragTo(x2, y2, duration=duration, button=button)


def press_key(key, times=1):
    """按键"""
    for _ in range(times):
        pyautogui.press(key)
    print(f"  [key] {key} x{times}")


def wait(seconds, label=""):
    if label:
        print(f"  [wait] {label} {seconds}s")
    time.sleep(seconds)


def main():
    proc = None
    try:
        proc = launch_game()
        wait(5, "游戏启动")

        win = find_game_window(timeout=60)
        activate_window(win)
        wait(3, "CA 关卡加载")

        print("\n=== 步骤1: 记录初始画面 ===")
        shot_initial = screenshot(win, "01_initial")

        print("\n=== 步骤2: 模拟玩家旋转视角（右键拖拽） ===")
        drag_relative(win, (0.55, 0.45), (0.40, 0.45), duration=0.6, button="right")
        wait(1, "视角稳定")
        shot_rotated = screenshot(win, "02_view_rotated")

        rotate_diff = image_diff_ratio(shot_initial, shot_rotated)
        print(f"  [check] 旋转视角前后中心区域差异: {rotate_diff:.2%}")
        assert rotate_diff > 0.001, "视角旋转后画面无变化，相机控制可能失效"

        print("\n=== 步骤3: 点击中心区域创建/切换几个细胞 ===")
        # 在 3D 视图中央附近密集点击，模拟玩家搭建初始结构
        cells = [
            (0.50, 0.45),
            (0.51, 0.45),
            (0.49, 0.45),
            (0.50, 0.46),
            (0.50, 0.44),
            (0.48, 0.46),
            (0.52, 0.46),
            (0.50, 0.48),
        ]
        for rx, ry in cells:
            click_relative(win, rx, ry)
            wait(0.2)
        wait(1, "画面稳定")
        shot_after_click = screenshot(win, "03_after_click")

        click_diff = image_diff_ratio(shot_rotated, shot_after_click)
        print(f"  [check] 点击前后中心区域差异: {click_diff:.2%}")
        assert click_diff > 0.002, "点击后画面无明显变化，CA 细胞切换可能失效"

        print("\n=== 步骤4: 按 N 键单步演化 ===")
        press_key("n", times=1)
        wait(1.0, "单步稳定")
        shot_stepped = screenshot(win, "04_after_steps")

        step_diff = image_diff_ratio(shot_after_click, shot_stepped)
        print(f"  [check] N 键单步前后中心区域差异: {step_diff:.2%}")
        assert step_diff > 0.001, "N 键单步后画面无变化，单步演化可能失效"

        print("\n=== 步骤5: 按空格启动自动演化 ===")
        press_key("space")
        wait(2.0, "自动演化运行")
        shot_running = screenshot(win, "05_auto_evolve_running")
        press_key("space")
        wait(0.5, "暂停稳定")

        run_diff = image_diff_ratio(shot_stepped, shot_running)
        print(f"  [check] 自动演化前后中心区域差异: {run_diff:.2%}")
        assert run_diff > 0.001, "自动演化画面无变化，CA 演化可能未运行"

        print("\n=== 步骤6: 再旋转视角观察不同角度 ===")
        drag_relative(win, (0.45, 0.40), (0.55, 0.50), duration=0.6, button="right")
        wait(1, "视角稳定")
        shot_final = screenshot(win, "06_final_view")

        final_diff = image_diff_ratio(shot_running, shot_final)
        print(f"  [check] 最终旋转前后中心区域差异: {final_diff:.2%}")
        assert final_diff > 0.001, "最终视角旋转后画面无变化"

        print("\n=== 全部 CA 自动化测试通过 ===")
        print(f"截图保存位置: {SHOT_DIR}")
        return 0

    except KeyboardInterrupt:
        print("\n[中断] 用户手动终止")
        return 1
    except Exception as e:
        print(f"\n[失败] {e}")
        return 1
    finally:
        if proc:
            print("[cleanup] 关闭游戏进程")
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()


if __name__ == "__main__":
    sys.exit(main())
