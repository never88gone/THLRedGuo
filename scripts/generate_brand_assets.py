#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

root = Path(__file__).resolve().parents[1]

def make_round_icon(img):
    """生成带圆形遮罩的自适应圆形图标"""
    w, h = img.size
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, w, h), fill=255)
    rounded = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    rounded.paste(img.convert('RGBA'), (0, 0), mask=mask)
    return rounded

def make_rounded_rect(img, radius):
    """生成带微圆角的图标"""
    w, h = img.size
    mask = Image.new('L', (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, w, h), radius=radius, fill=255)
    result = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    result.paste(img.convert('RGBA'), (0, 0), mask=mask)
    return result

def get_font(size):
    candidate_fonts = [
        '/System/Library/Fonts/STHeiti Medium.ttc',
        '/System/Library/Fonts/STHeiti Light.ttc',
        '/System/Library/Fonts/PingFang.ttc',
        '/Library/Fonts/Arial Unicode.ttf',
    ]
    for path in candidate_fonts:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                continue
    return ImageFont.load_default()

def main():
    parser = argparse.ArgumentParser(description='从 tvOS 图标生成多端（iOS、macOS、Android、Windows）品牌资源')
    default_input = root / 'assets/branding/source_banner.jpg'
    if not default_input.exists():
        default_input = root / 'tvos/THLRedLook/Assets.xcassets/AppIcon.appiconset/image.png'
    parser.add_argument('--input', type=Path, default=default_input,
                        help='母图路径（默认使用横幅源图并做居中裁切充满正方形）')
    parser.add_argument('--output', type=Path, default=root)
    options = parser.parse_args()
    output = options.output

    if not options.input.exists():
        raise SystemExit(f'母图标文件不存在：{options.input}')

    print(f'正在读取源图标: {options.input.relative_to(root) if options.input.is_relative_to(root) else options.input}')
    raw_img = Image.open(options.input).convert('RGB')

    # 若为非正方形横幅，执行居中等比裁切充满 1024x1024，去除任何上下黑边，自然铺满黑到暗红光影渐变色
    if raw_img.width != raw_img.height:
        print(f'  -> 源图尺寸为 {raw_img.size}，正在执行等比居中裁切充满 1024x1024 (消除黑边)...')
        src_icon = ImageOps.fit(raw_img, (1024, 1024), method=Image.Resampling.LANCZOS)
    else:
        src_icon = raw_img.resize((1024, 1024), Image.Resampling.LANCZOS)

    # 0. 保存项目统一资产母图
    branding_dir = output / 'assets/branding'
    branding_dir.mkdir(parents=True, exist_ok=True)
    src_icon.save(branding_dir / 'app_icon.png', 'PNG')
    print(f'  -> 已保存跨平台正方形母图 (充满渐变无黑边) 到 assets/branding/app_icon.png')

    def save_file(img, rel_path, fmt=None):
        dest = output / rel_path
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest, format=fmt)

    # 1. iOS AppIcon
    ios_json_path = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'
    if ios_json_path.exists():
        contents_ios = json.loads(ios_json_path.read_text())
        for entry in contents_ios.get('images', []):
            if 'filename' in entry:
                size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
                resized = src_icon.resize((size, size), Image.Resampling.LANCZOS)
                # App Store 规范：1024x1024 必须是纯 RGB，无 Alpha
                if entry.get('idiom') == 'ios-marketing' or size == 1024:
                    resized = resized.convert('RGB')
                save_file(resized, f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{entry["filename"]}', 'PNG')
        print('  -> 已生成 iOS 图标集 (ios/Runner/Assets.xcassets/AppIcon.appiconset/)')

    # 2. macOS AppIcon
    macos_json_path = root / 'macos/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json'
    if macos_json_path.exists():
        contents_mac = json.loads(macos_json_path.read_text())
        for entry in contents_mac.get('images', []):
            if 'filename' in entry:
                size = round(float(entry['size'].split('x')[0]) * float(entry['scale'].rstrip('x')))
                resized = src_icon.resize((size, size), Image.Resampling.LANCZOS)
                save_file(resized, f'macos/Runner/Assets.xcassets/AppIcon.appiconset/{entry["filename"]}', 'PNG')
        print('  -> 已生成 macOS 图标集 (macos/Runner/Assets.xcassets/AppIcon.appiconset/)')

    # 3. Windows ICO
    ico_sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    ico_dest = output / 'windows/runner/resources/app_icon.ico'
    ico_dest.parent.mkdir(parents=True, exist_ok=True)
    src_icon.save(ico_dest, format='ICO', sizes=ico_sizes)
    print('  -> 已生成 Windows 多尺寸图标 (windows/runner/resources/app_icon.ico)')

    # 4. Android 图标 (标准 mipmap 系列)
    android_densities = {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
    }
    for density, px in android_densities.items():
        resized = src_icon.resize((px, px), Image.Resampling.LANCZOS)
        save_file(resized, f'android/app/src/main/res/mipmap-{density}/ic_launcher.png', 'PNG')
        
        round_icon = make_round_icon(resized)
        save_file(round_icon, f'android/app/src/main/res/mipmap-{density}/ic_launcher_round.png', 'PNG')
    print('  -> 已生成 Android 标准 mipmap 图标集及圆角图标 (ic_launcher.png, ic_launcher_round.png)')

    # 5. Android TV 横幅 (640x360)
    font = get_font(68)
    for resource in ['tv_banner', 'tv_banner_all_sources']:
        banner = Image.new('RGB', (640, 360), (12, 4, 8))
        icon_thumb = src_icon.resize((180, 180), Image.Resampling.LANCZOS)
        icon_thumb_rounded = make_rounded_rect(icon_thumb, radius=32)
        banner.paste(icon_thumb_rounded, (44, 90), mask=icon_thumb_rounded)
        
        draw = ImageDraw.Draw(banner)
        draw.text((250, 142), '糖葫芦果鉴', font=font, fill='white')
        save_file(banner, f'android/app/src/main/res/drawable-xhdpi/{resource}.png', 'PNG')
    # 6. iOS LaunchImage 启动图 (圆角精致 Logo 居中呈现)
    ios_launch_dir = output / 'ios/Runner/Assets.xcassets/LaunchImage.imageset'
    if ios_launch_dir.exists():
        for scale_name, px in [('LaunchImage.png', 128), ('LaunchImage@2x.png', 256), ('LaunchImage@3x.png', 384)]:
            logo = src_icon.resize((px, px), Image.Resampling.LANCZOS)
            logo_rounded = make_rounded_rect(logo, radius=int(px * 0.22))
            save_file(logo_rounded, f'ios/Runner/Assets.xcassets/LaunchImage.imageset/{scale_name}', 'PNG')
        print('  -> 已生成 iOS LaunchImage 启动图 (LaunchImage.png, @2x, @3x)')

    # 7. Android 启动图 (splash_logo)
    for density, px in [('mdpi', 96), ('hdpi', 144), ('xhdpi', 192), ('xxhdpi', 288), ('xxxhdpi', 384)]:
        logo = src_icon.resize((px, px), Image.Resampling.LANCZOS)
        logo_rounded = make_rounded_rect(logo, radius=int(px * 0.22))
        save_file(logo_rounded, f'android/app/src/main/res/drawable-{density}/splash_logo.png', 'PNG')
    base_logo = src_icon.resize((192, 192), Image.Resampling.LANCZOS)
    save_file(make_rounded_rect(base_logo, radius=42), 'android/app/src/main/res/drawable/splash_logo.png', 'PNG')
    print('  -> 已生成 Android 启动图资源 (drawable/splash_logo.png 及多密度适配)')

    print('\n✅ 所有平台图标与启动图资源已成功由母图生成并对齐！')

if __name__ == '__main__':
    main()
