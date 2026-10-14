#!/usr/bin/env python3
"""
生成规范、纯净的 tvOS 品牌资产：
1. Top Shelf / Top Shelf Wide：单层一体化海报，消除重叠双层图与黑方块，主体限制在 52% 安全高度
2. LaunchBackground：纯深黑暗红渐变背景（用于系统 UILaunchScreen，彻底解决启动时系统提前绘制静态图导致的闪烁与位移）
3. LaunchLogo：纯净独立透明通道 Logo，无文字，用于 SwiftUI 启动时的 Spring 弹出动效
4. LaunchImage：备用单层纯净启动图（无文字）
"""

import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance

ROOT_DIR = Path("/Volumes/MacintoshData/Work/Github/guoapp1")
ASSETS_DIR = ROOT_DIR / "tvos" / "THLRedLook" / "Assets.xcassets"
SRC_WIDE = Path("/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed/tvos_icon_c_redgrad_1791104121444.jpg")

def create_ambient_background(width: int, height: int) -> Image.Image:
    """生成优雅深邃的黑红微质感渐变背景（四周暗黑，中心温润深红光晕，饱满高级，非死黑）"""
    src = Image.open(SRC_WIDE).convert("RGB")
    sw, sh = src.size
    
    bg = src.copy()
    draw = ImageDraw.Draw(bg)
    draw.ellipse([sw * 0.28, sh * 0.20, sw * 0.72, sh * 0.80], fill=(70, 15, 30))
    
    bg_blurred = bg.filter(ImageFilter.GaussianBlur(radius=55))
    
    enhancer_c = ImageEnhance.Contrast(bg_blurred)
    bg_enhanced = enhancer_c.enhance(1.25)
    enhancer_s = ImageEnhance.Color(bg_enhanced)
    bg_final = enhancer_s.enhance(1.3)
    
    return bg_final.resize((width, height), Image.Resampling.LANCZOS)

def extract_clean_subject() -> Image.Image:
    """从原图提取中心发光糖葫芦及播放光三角主体（羽化边缘，透明通道，无文字）"""
    src = Image.open(SRC_WIDE).convert("RGBA")
    # 裁剪主体区域，避开底部任何文字
    crop_box = (200, 40, 1176, 680)
    subject = src.crop(crop_box)
    sw, sh = subject.size

    # 制作径向渐变羽化 mask
    mask = Image.new("L", (sw, sh), 0)
    draw = ImageDraw.Draw(mask)
    cx, cy = sw / 2, sh / 2
    rx, ry = sw * 0.46, sh * 0.46

    for i in range(256):
        factor = 1.0 - (i / 255.0)
        cur_rx = rx * factor
        cur_ry = ry * factor
        bbox = [cx - cur_rx, cy - cur_ry, cx + cur_rx, cy + cur_ry]
        draw.ellipse(bbox, fill=int(255 * (1.0 - factor**2)))

    mask = mask.filter(ImageFilter.GaussianBlur(radius=25))
    subject.putalpha(mask)
    return subject

def generate_single_layer_topshelf(width: int, height: int, subject: Image.Image) -> Image.Image:
    """生成绝对单层的安全画幅 Top Shelf 海报（无重叠双层图，无黑块）"""
    bg = create_ambient_background(width, height)
    
    # 主体高度设为 50% 安全画幅
    target_h = int(height * 0.50)
    target_w = int(subject.width * (target_h / float(subject.height)))
    resized_subj = subject.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    sx = (width - target_w) // 2
    sy = (height - target_h) // 2
    bg.paste(resized_subj, (sx, sy), resized_subj)
    return bg.convert("RGB")

def main():
    print("=== 开始生成全新标准化 tvOS 单层海报与无闪烁启动资产 ===")
    subject = extract_clean_subject()

    # 1. 导出独立纯净 LaunchLogo (512x512, 1024x1024)
    logo_dir = ASSETS_DIR / "LaunchLogo.imageset"
    logo_dir.mkdir(parents=True, exist_ok=True)
    
    # 正方形纯主体
    l_size = max(subject.width, subject.height)
    square_logo = Image.new("RGBA", (l_size, l_size), (0, 0, 0, 0))
    square_logo.paste(subject, ((l_size - subject.width) // 2, (l_size - subject.height) // 2), subject)
    
    logo_1x = square_logo.resize((512, 512), Image.Resampling.LANCZOS)
    logo_1x.save(logo_dir / "LaunchLogo.png", "PNG")
    logo_2x = square_logo.resize((1024, 1024), Image.Resampling.LANCZOS)
    logo_2x.save(logo_dir / "LaunchLogo@2x.png", "PNG")
    
    logo_json = '''{
  "images" : [
    {
      "filename" : "LaunchLogo.png",
      "idiom" : "tv",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchLogo@2x.png",
      "idiom" : "tv",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}'''
    (logo_dir / "Contents.json").write_text(logo_json)
    print("  ✓ LaunchLogo.imageset (纯净透明 Logo) 创建成功")

    # 2. 导出纯背景 LaunchBackground (1920x1080, 3840x2160)
    bg_dir = ASSETS_DIR / "LaunchBackground.imageset"
    bg_dir.mkdir(parents=True, exist_ok=True)
    
    bg_1x = create_ambient_background(1920, 1080).convert("RGB")
    bg_1x.save(bg_dir / "LaunchBackground.png", "PNG")
    bg_2x = create_ambient_background(3840, 2160).convert("RGB")
    bg_2x.save(bg_dir / "LaunchBackground@2x.png", "PNG")
    
    bg_json = '''{
  "images" : [
    {
      "filename" : "LaunchBackground.png",
      "idiom" : "tv",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchBackground@2x.png",
      "idiom" : "tv",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}'''
    (bg_dir / "Contents.json").write_text(bg_json)
    print("  ✓ LaunchBackground.imageset (纯净冷启动底图，无文字无Logo) 创建成功")

    # 3. 导出单层 Top Shelf (1920x720, 3840x1440)
    ts_dir = ASSETS_DIR / "AppIcon.brandassets" / "Top Shelf Image.imageset"
    ts_1x = generate_single_layer_topshelf(1920, 720, subject)
    ts_1x.save(ts_dir / "TopShelf.png", "PNG")
    ts_2x = generate_single_layer_topshelf(3840, 1440, subject)
    ts_2x.save(ts_dir / "TopShelf@2x.png", "PNG")
    print("  ✓ Top Shelf Image.png (单层一体化海报) 生成完毕")

    # 4. 导出单层 Top Shelf Wide (2320x720, 4640x1440)
    tsw_dir = ASSETS_DIR / "AppIcon.brandassets" / "Top Shelf Image Wide.imageset"
    tsw_1x = generate_single_layer_topshelf(2320, 720, subject)
    tsw_1x.save(tsw_dir / "TopShelf.png", "PNG")
    tsw_2x = generate_single_layer_topshelf(4640, 1440, subject)
    tsw_2x.save(tsw_dir / "TopShelf@2x.png", "PNG")
    print("  ✓ Top Shelf Image Wide.png (单层一体化宽屏海报) 生成完毕")

    # 5. 更新 LaunchImage.imageset (纯背景+居中Logo，备用单层无字启动图)
    launch_dir = ASSETS_DIR / "LaunchImage.imageset"
    l_1x = generate_single_layer_topshelf(1920, 1080, subject)
    l_1x.save(launch_dir / "LaunchImage.png", "PNG")
    l_2x = generate_single_layer_topshelf(3840, 2160, subject)
    l_2x.save(launch_dir / "LaunchImage@2x.png", "PNG")
    print("  ✓ LaunchImage.png (纯净单层无文字) 生成完毕")

    print("\n✅ 所有 tvOS 单层海报与启动资产更新就绪！")

if __name__ == "__main__":
    main()
