# download_hdri.py - 帮助用户下载或自动获取 Poly Haven HDRI
# 用法: python scripts/tests/download_hdri.py

import os
import sys
import urllib.request
import webbrowser

# Poly Haven 官方 CDN 直链 (dl.polyhaven.org)
POLYHAVEN_CDN_URL = (
    "https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/studio_small_03_2k.hdr"
)
TARGET_DIR = os.path.join(os.path.dirname(__file__), "../../assets/third_party/polyhaven/")
TARGET_NAME = "studio_small_03_2k.hdr"


def download_direct() -> bool:
    """尝试从 Poly Haven CDN 直接下载 HDR 文件。"""
    target_path = os.path.join(TARGET_DIR, TARGET_NAME)
    os.makedirs(TARGET_DIR, exist_ok=True)

    if os.path.exists(target_path):
        print(f"[HDRI] 文件已存在，跳过下载: {target_path}")
        return True

    print(f"[HDRI] 正在从 CDN 下载: {POLYHAVEN_CDN_URL}")
    try:
        urllib.request.urlretrieve(POLYHAVEN_CDN_URL, target_path)
        size_mb = os.path.getsize(target_path) / (1024 * 1024)
        print(f"[HDRI] 下载成功: {target_path} ({size_mb:.2f} MB)")
        return True
    except Exception as e:
        print(f"[HDRI] 直接下载失败: {e}")
        return False


def open_manual() -> None:
    """打开浏览器引导用户手动下载。"""
    print("\n[HDRI] 请手动下载以下 HDRI 文件:")
    print("1. 打开 https://polyhaven.com/a/studio_small_03")
    print("2. 选择 2K 分辨率，下载 HDR 格式")
    print(f"3. 将文件放入: {os.path.abspath(TARGET_DIR)}")
    print(f"4. 命名为: {TARGET_NAME}")
    webbrowser.open("https://polyhaven.com/a/studio_small_03")


if __name__ == "__main__":
    if not download_direct():
        open_manual()
        sys.exit(1)
