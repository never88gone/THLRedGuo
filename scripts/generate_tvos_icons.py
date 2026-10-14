#!/usr/bin/env python3
import os
from PIL import Image, ImageOps

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCAL_SRC = os.path.join(ROOT_DIR, "assets", "branding", "source_banner.jpg")
SRC_IMAGE = LOCAL_SRC if os.path.exists(LOCAL_SRC) else "/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed/tvos_icon_c_redgrad_1791104121444.jpg"
ASSETS_DIR = os.path.join(ROOT_DIR, "tvos", "THLRedLook", "Assets.xcassets")

def make_centered_fit(src_img, target_size, bg_color=(12, 4, 8)):
    """等比例居中适应目标尺寸，四周以平滑深暗红背景色延展填充（严格 RGB 无 Alpha）"""
    tw, th = target_size
    sw, sh = src_img.size
    
    scale = min(tw / sw, th / sh)
    nw, nh = int(sw * scale), int(sh * scale)
    resized = src_img.resize((nw, nh), Image.Resampling.LANCZOS)
    
    out = Image.new("RGB", (tw, th), bg_color)
    ox = (tw - nw) // 2
    oy = (th - nh) // 2
    out.paste(resized, (ox, oy))
    return out

def make_cropped_fill(src_img, target_size):
    """等比例裁切充满目标画幅，保留居中核心视觉主体，消除任何黑边填充，完整呈现背景光影渐变"""
    return ImageOps.fit(src_img, target_size, method=Image.Resampling.LANCZOS)

def main():
    print(f"正在读取方案 C (黑到暗红渐变底) 源图: {SRC_IMAGE}")
    src = Image.open(SRC_IMAGE).convert("RGB")
    
    # 1. 1024x1024 Universal AppIcon & applogo (采用居中等比裁切充满正方形，去除上下黑边，铺满原生渐变色)
    icon_1024 = make_cropped_fill(src, (1024, 1024))
    
    appicon_dir = os.path.join(ASSETS_DIR, "AppIcon.appiconset")
    icon_1024.save(os.path.join(appicon_dir, "image.png"), "PNG")
    icon_1024.save(os.path.join(appicon_dir, "image 1.png"), "PNG")
    print("  -> 已生成 AppIcon.appiconset (1024x1024 RGB 裁切充满无黑边)")
    
    applogo_dir = os.path.join(ASSETS_DIR, "applogo.imageset")
    icon_1024.save(os.path.join(applogo_dir, "image.png"), "PNG")
    print("  -> 已生成 applogo.imageset (1024x1024 RGB 裁切充满无黑边)")
    
    # 2. Top Shelf Banner (1920x720 & 2320x720)
    top_shelf_1x = make_cropped_fill(src, (1920, 720))
    top_shelf_2x = make_cropped_fill(src, (3840, 1440))
    ts_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/Top Shelf Image.imageset")
    top_shelf_1x.save(os.path.join(ts_dir, "TopShelf.png"), "PNG")
    top_shelf_2x.save(os.path.join(ts_dir, "TopShelf@2x.png"), "PNG")
    print("  -> 已生成 Top Shelf Image (1920x720, 3840x1440 RGB)")
    
    top_shelf_w_1x = make_cropped_fill(src, (2320, 720))
    top_shelf_w_2x = make_cropped_fill(src, (4640, 1440))
    ts_w_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/Top Shelf Image Wide.imageset")
    top_shelf_w_1x.save(os.path.join(ts_w_dir, "TopShelf.png"), "PNG")
    top_shelf_w_2x.save(os.path.join(ts_w_dir, "TopShelf@2x.png"), "PNG")
    print("  -> 已生成 Top Shelf Image Wide (2320x720, 4640x1440 RGB)")
    
    # 3. Small App Icon (400x240 @1x, 800x480 @2x, 比例 5:3)
    small_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/App Icon - Small.imagestack")
    small_back_1x = make_cropped_fill(src, (400, 240))
    small_back_2x = make_cropped_fill(src, (800, 480))
    
    small_back_dir = os.path.join(small_dir, "Back.imagestacklayer/Content.imageset")
    small_back_1x.save(os.path.join(small_back_dir, "icon-back.png"), "PNG")
    small_back_2x.save(os.path.join(small_back_dir, "icon-back@2x.png"), "PNG")
    
    # 前景浮雕层 (正方形居中主体)
    crop_size = min(src.width, src.height)
    left = (src.width - crop_size) // 2
    top = (src.height - crop_size) // 2
    center_square = src.crop((left, top, left + crop_size, top + crop_size))
    
    small_front_1x = center_square.resize((180, 180), Image.Resampling.LANCZOS).convert("RGBA")
    small_front_2x = center_square.resize((360, 360), Image.Resampling.LANCZOS).convert("RGBA")
    
    small_front_dir = os.path.join(small_dir, "Front.imagestacklayer/Content.imageset")
    small_front_1x.save(os.path.join(small_front_dir, "AppIcon-Large.png"), "PNG")
    small_front_2x.save(os.path.join(small_front_dir, "AppIcon-Large@2x.png"), "PNG")
    print("  -> 已生成 App Icon - Small.imagestack (Back: 400x240/800x480 RGB, Front: 180x180/360x360 RGBA)")
    
    # 4. Large App Icon (1280x768 @1x, 2560x1536 @2x, 比例 5:3)
    large_dir = os.path.join(ASSETS_DIR, "AppIcon.brandassets/App Icon - Large.imagestack")
    large_back_1x = make_cropped_fill(src, (1280, 768))
    large_back_2x = make_cropped_fill(src, (2560, 1536))
    
    large_back_dir = os.path.join(large_dir, "Back.imagestacklayer/Content.imageset")
    large_back_1x.save(os.path.join(large_back_dir, "icon-back.png"), "PNG")
    large_back_2x.save(os.path.join(large_back_dir, "icon-back@2x.png"), "PNG")
    
    large_front_1x = center_square.resize((720, 720), Image.Resampling.LANCZOS).convert("RGBA")
    large_front_2x = center_square.resize((1440, 1440), Image.Resampling.LANCZOS).convert("RGBA")
    
    large_front_dir = os.path.join(large_dir, "Front.imagestacklayer/Content.imageset")
    large_front_1x.save(os.path.join(large_front_dir, "AppIcon-Large.png"), "PNG")
    large_front_2x.save(os.path.join(large_front_dir, "AppIcon-Large@2x.png"), "PNG")
    print("  -> 已生成 App Icon - Large.imagestack (Back: 1280x768/2560x1536 RGB, Front: 720x720/1440x1440 RGBA)")
    
    print("\n✅ 所有 tvOS 规格要求图标已使用方案 C (黑到暗红渐变底) 成功覆盖生成！")

if __name__ == "__main__":
    main()
