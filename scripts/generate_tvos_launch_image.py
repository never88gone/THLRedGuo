#!/usr/bin/env python3
import os
import shutil
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

SRC_IMAGE = "/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed/tvos_icon_c_redgrad_1791104121444.jpg"
ASSETS_DIR = Path("/Volumes/MacintoshData/Work/Github/guoapp1/tvos/THLRedLook/Assets.xcassets")
ARTIFACT_DIR = Path("/Users/never88gone/.gemini/antigravity/brain/dbf2b53c-5671-4a31-92a9-6fe0c48be0ed")

FONT_PATH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
if not os.path.exists(FONT_PATH):
    FONT_PATH = "/System/Library/Fonts/STHeiti Medium.ttc"

def generate_launch_image(width, height, scale_factor=1.0):
    src = Image.open(SRC_IMAGE).convert("RGB")
    
    # 1. 精确缩放填充 1920x1080 / 3840x2160 宽屏画幅 (完全无黑框，整张图就是黑到暗红渐变)
    # 1376x768 裁切充满 1920x1080 (宽高比 1.791 vs 1.777)
    target_ratio = width / height
    src_ratio = src.width / src.height
    
    if src_ratio > target_ratio:
        # 源图偏宽，裁切两边
        new_w = int(src.height * target_ratio)
        left = (src.width - new_w) // 2
        cropped = src.crop((left, 0, left + new_w, src.height))
    else:
        # 源图偏高，裁切上下
        new_h = int(src.width / target_ratio)
        top = (src.height - new_h) // 2
        cropped = src.crop((0, top, src.width, top + new_h))
        
    img = cropped.resize((width, height), Image.Resampling.LANCZOS)
    
    # 2. 在下方空旷渐变区域自然融入中文品牌排版
    draw = ImageDraw.Draw(img)
    
    title_size = int(52 * scale_factor)
    subtitle_size = int(22 * scale_factor)
    copy_size = int(14 * scale_factor)
    
    try:
        title_font = ImageFont.truetype(FONT_PATH, title_size)
        subtitle_font = ImageFont.truetype(FONT_PATH, subtitle_size)
        copy_font = ImageFont.truetype(FONT_PATH, copy_size)
    except Exception:
        title_font = ImageFont.load_default()
        subtitle_font = ImageFont.load_default()
        copy_font = ImageFont.load_default()
        
    title_text = "糖葫芦Haw"
    subtitle_text = "极速 · 纯净 · 独立端侧影视体验"
    copy_text = "THL RedLook for Apple tvOS"
    
    # 阴影层
    text_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    t_draw = ImageDraw.Draw(text_layer)
    
    # 主标题位置（在下半部分偏上一点，糖葫芦光晕正下方）
    t_bbox = t_draw.textbbox((0, 0), title_text, font=title_font)
    t_w = t_bbox[2] - t_bbox[0]
    t_x = (width - t_w) // 2
    t_y = int(height * 0.77)
    
    # 阴影与微光
    t_draw.text((t_x, t_y + int(3 * scale_factor)), title_text, font=title_font, fill=(0, 0, 0, 200))
    t_draw.text((t_x, t_y), title_text, font=title_font, fill=(255, 255, 255, 250))
    
    # 副标题
    s_bbox = t_draw.textbbox((0, 0), subtitle_text, font=subtitle_font)
    s_w = s_bbox[2] - s_bbox[0]
    s_x = (width - s_w) // 2
    s_y = t_y + (t_bbox[3] - t_bbox[1]) + int(14 * scale_factor)
    
    t_draw.text((s_x, s_y + int(2 * scale_factor)), subtitle_text, font=subtitle_font, fill=(0, 0, 0, 160))
    t_draw.text((s_x, s_y), subtitle_text, font=subtitle_font, fill=(230, 210, 215, 200))
    
    # 版权小字
    c_bbox = t_draw.textbbox((0, 0), copy_text, font=copy_font)
    c_w = c_bbox[2] - c_bbox[0]
    c_x = (width - c_w) // 2
    c_y = height - int(45 * scale_factor)
    t_draw.text((c_x, c_y), copy_text, font=copy_font, fill=(160, 120, 130, 140))
    
    img = Image.alpha_composite(img.convert("RGBA"), text_layer).convert("RGB")
    return img

def main():
    print("=== 使用方案 C 原始宽屏源图生成纯净无黑框 tvOS 启动图 ===")
    launch_image_dir = ASSETS_DIR / "LaunchImage.imageset"
    launch_image_dir.mkdir(parents=True, exist_ok=True)
    
    print("1. 生成 1920x1080 (1x)...")
    img_1x = generate_launch_image(1920, 1080, scale_factor=1.0)
    img_1x.save(launch_image_dir / "LaunchImage.png", "PNG")
    
    print("2. 生成 3840x2160 (2x, 4K)...")
    img_2x = generate_launch_image(3840, 2160, scale_factor=2.0)
    img_2x.save(launch_image_dir / "LaunchImage@2x.png", "PNG")
    
    contents_json = """{
  "images" : [
    {
      "filename" : "LaunchImage.png",
      "idiom" : "tv",
      "scale" : "1x"
    },
    {
      "filename" : "LaunchImage@2x.png",
      "idiom" : "tv",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
    (launch_image_dir / "Contents.json").write_text(contents_json, encoding="utf-8")
    print(f"  -> 已成功生成 LaunchImage.imageset 至: {launch_image_dir}")
    
    if ARTIFACT_DIR.exists():
        artifact_file = ARTIFACT_DIR / "tvos_launch_image_c_wide.png"
        shutil.copy2(launch_image_dir / "LaunchImage.png", artifact_file)
        print(f"  -> 已同步工件预览图至: {artifact_file}")

if __name__ == "__main__":
    main()
