#!/usr/bin/env python3
"""
生成 tvOS 全套 App 图标与 Top Shelf 宽屏资产
基于最新 AI 精心制作的糖葫芦果鉴（THLRedLook）专属 3D 玻璃态冰糖葫芦播放器图标
"""

import os
from PIL import Image, ImageFilter

SOURCE_IMG_PATH = "/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed/thl_redlook_icon_flat_1791096719320.jpg"
ASSETS_DIR = "/Volumes/MacintoshData/Work/Github/guoapp1/tvos/THLRedLook/Assets.xcassets"

def make_transparent_front(src_img: Image.Image, threshold: int = 15) -> Image.Image:
    """
    根据纯暗底提取带有半透明光晕的前景主体
    """
    rgba = src_img.convert("RGBA")
    data = rgba.getdata()
    new_data = []
    for item in data:
        r, g, b, a = item
        # 计算背景暗度（纯黑/极深蓝黑）
        brightness = max(r, g, b)
        if brightness <= threshold:
            new_data.append((0, 0, 0, 0))
        elif brightness < 60:
            alpha = int(255 * ((brightness - threshold) / (60 - threshold)))
            new_data.append((r, g, b, min(255, alpha)))
        else:
            new_data.append((r, g, b, 255))
    rgba.putdata(new_data)
    return rgba

def generate_assets():
    if not os.path.exists(SOURCE_IMG_PATH):
        raise FileNotFoundError(f"Source icon not found at {SOURCE_IMG_PATH}")
    
    src = Image.open(SOURCE_IMG_PATH).convert("RGB")
    print(f"Loaded source image: {src.size}")

    # 1. 1024x1024 AppIcon.appiconset
    appicon_dir = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
    os.makedirs(appicon_dir, exist_ok=True)
    src.save(os.path.join(appicon_dir, "image.png"), "PNG")
    src.save(os.path.join(appicon_dir, "image 1.png"), "PNG")
    print("✓ Saved 1024x1024 AppIcon.appiconset")

    # 2. applogo.imageset
    applogo_dir = os.path.join(ASSETS_DIR, "applogo.imageset")
    os.makedirs(applogo_dir, exist_ok=True)
    src.save(os.path.join(applogo_dir, "image.png"), "PNG")
    print("✓ Saved applogo.imageset")

    # 提取透明前景
    front_rgba = make_transparent_front(src, threshold=12)

    # 3. 创建深邃大屏背景（深暗蓝黑与微弱中心渐变）
    def create_background(w: int, h: int) -> Image.Image:
        bg = Image.new("RGBA", (w, h), (10, 13, 20, 255))
        return bg

    # 4. App Icon - Large (1280x768)
    large_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/App Icon - Large.imagestack")
    large_front_dir = os.path.join(large_dir, "Front.imagestacklayer/Content.imageset")
    large_back_dir = os.path.join(large_dir, "Back.imagestacklayer/Content.imageset")
    os.makedirs(large_front_dir, exist_ok=True)
    os.makedirs(large_back_dir, exist_ok=True)

    # Large Back
    create_background(1280, 768).save(os.path.join(large_back_dir, "icon-back.png"), "PNG")
    create_background(2560, 1536).save(os.path.join(large_back_dir, "icon-back@2x.png"), "PNG")

    # Large Front (720x720, 1440x1440)
    front_rgba.resize((720, 720), Image.Resampling.LANCZOS).save(os.path.join(large_front_dir, "AppIcon-Large.png"), "PNG")
    front_rgba.resize((1440, 1440), Image.Resampling.LANCZOS).save(os.path.join(large_front_dir, "AppIcon-Large@2x.png"), "PNG")
    print("✓ Saved App Icon - Large.imagestack")

    # 5. App Icon - Small (400x240)
    small_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/App Icon - Small.imagestack")
    small_front_dir = os.path.join(small_dir, "Front.imagestacklayer/Content.imageset")
    small_back_dir = os.path.join(small_dir, "Back.imagestacklayer/Content.imageset")
    os.makedirs(small_front_dir, exist_ok=True)
    os.makedirs(small_back_dir, exist_ok=True)

    # Small Back
    create_background(400, 240).save(os.path.join(small_back_dir, "icon-back.png"), "PNG")
    create_background(800, 480).save(os.path.join(small_back_dir, "icon-back@2x.png"), "PNG")

    # Small Front (180x180, 360x360)
    front_rgba.resize((180, 180), Image.Resampling.LANCZOS).save(os.path.join(small_front_dir, "AppIcon-Large.png"), "PNG")
    front_rgba.resize((360, 360), Image.Resampling.LANCZOS).save(os.path.join(small_front_dir, "AppIcon-Large@2x.png"), "PNG")
    print("✓ Saved App Icon - Small.imagestack")

    # 6. Top Shelf Image (1920x720, 3840x1440) & Top Shelf Image Wide (2320x720, 4640x1440)
    def render_top_shelf(w: int, h: int, icon_size: int) -> Image.Image:
        shelf = create_background(w, h)
        resized_front = front_rgba.resize((icon_size, icon_size), Image.Resampling.LANCZOS)
        x = (w - icon_size) // 2
        y = (h - icon_size) // 2
        shelf.paste(resized_front, (x, y), resized_front)
        return shelf

    shelf_norm_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/Top Shelf Image.imageset")
    shelf_wide_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/Top Shelf Image Wide.imageset")
    os.makedirs(shelf_norm_dir, exist_ok=True)
    os.makedirs(shelf_wide_dir, exist_ok=True)

    render_top_shelf(1920, 720, 640).save(os.path.join(shelf_norm_dir, "TopShelf.png"), "PNG")
    render_top_shelf(3840, 1440, 1280).save(os.path.join(shelf_norm_dir, "TopShelf@2x.png"), "PNG")
    print("✓ Saved Top Shelf Image")

    render_top_shelf(2320, 720, 640).save(os.path.join(shelf_wide_dir, "TopShelf.png"), "PNG")
    render_top_shelf(4640, 1440, 1280).save(os.path.join(shelf_wide_dir, "TopShelf@2x.png"), "PNG")
    print("✓ Saved Top Shelf Image Wide")

    print("\n[INFO] 全部 tvOS App 图标与宽屏资产生成完毕！")

if __name__ == "__main__":
    generate_assets()
