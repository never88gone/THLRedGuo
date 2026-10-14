#!/usr/bin/env python3
import os
import math
from PIL import Image, ImageDraw, ImageFont

POSTERS_DIR = "tvos/THLRedLook/AssetsData/Posters"
os.makedirs(POSTERS_DIR, exist_ok=True)

# 16部经典爆款短剧定义与色彩美学体系
DRAMAS = [
    ("顾总的天价前妻", "都市 · 甜宠 · 虐恋", (140, 20, 40), (40, 10, 25), "9.9"),
    ("狂龙出狱", "战神 · 逆袭 · 暴爽", (180, 50, 10), (35, 15, 8), "9.8"),
    ("重返1990首富", "年代 · 商业 · 暴富", (160, 110, 20), (40, 25, 10), "9.7"),
    ("天降豪婿", "豪门 · 隐忍 · 逆袭", (30, 80, 160), (10, 20, 50), "9.8"),
    ("绝品龙皇", "玄幻 · 至尊 · 无敌", (100, 30, 150), (25, 10, 45), "9.9"),
    ("我的极品女总裁", "职场 · 商业 · 悬疑", (20, 120, 130), (8, 30, 40), "9.6"),
    ("战神归来当奶爸", "温情 · 热血 · 守护", (170, 70, 30), (45, 20, 15), "9.8"),
    ("镇国神医", "医道 · 传奇 · 救世", (30, 130, 80), (10, 35, 20), "9.7"),
    ("隐藏的首富继承人", "豪门 · 揭秘 · 争锋", (130, 100, 40), (35, 25, 12), "9.8"),
    ("太子爷的小娇妻", "甜宠 · 独占 · 浪漫", (180, 40, 90), (50, 15, 30), "9.9"),
    ("至尊龙帅", "军武 · 热血 · 荡寇", (50, 70, 100), (15, 22, 35), "9.7"),
    ("重生之狂暴逆袭", "复仇 · 爽剧 · 称霸", (160, 25, 25), (45, 8, 10), "9.8"),
    ("女总裁的贴身兵王", "都市 · 保镖 · 决斗", (40, 50, 130), (12, 18, 45), "9.6"),
    ("仙尊下山", "仙侠 · 奇幻 · 纵横", (110, 40, 160), (30, 12, 50), "9.9"),
    ("大唐逍遥驸马爷", "历史 · 穿越 · 轻松", (170, 45, 35), (50, 15, 15), "9.7"),
    ("顶级特工在都市", "动作 · 谍战 · 悬疑", (30, 90, 110), (10, 28, 38), "9.8"),
]

def draw_poster(index, title, tags, color_top, color_bot, score):
    w, h = 600, 882
    img = Image.new('RGB', (w, h), color=(15, 15, 20))
    draw = ImageDraw.Draw(img)

    # 1. 绘制高质感电影光影双向渐变背景
    for y in range(h):
        t = y / h
        # 加入呼吸光晕曲线
        light = math.sin(t * math.pi) * 0.35
        r = int(color_top[0] * (1 - t) + color_bot[0] * t + 80 * light)
        g = int(color_top[1] * (1 - t) + color_bot[1] * t + 60 * light)
        b = int(color_top[2] * (1 - t) + color_bot[2] * t + 90 * light)
        r = max(0, min(255, r))
        g = max(0, min(255, g))
        b = max(0, min(255, b))
        draw.line([(0, y), (w, y)], fill=(r, g, b))

    # 2. 绘制星光/微光粒子装饰
    for i in range(40):
        px = (index * 73 + i * 37) % w
        py = (index * 59 + i * 43) % int(h * 0.7)
        radius = (i % 3) + 1
        alpha_val = int(120 + 80 * math.sin(i))
        draw.ellipse([px - radius, py - radius, px + radius, py + radius], fill=(255, 255, 255))

    # 3. 绘制中心具有视觉冲击力的大电影图形图腾（聚光环与几何棱镜）
    cx, cy = w // 2, int(h * 0.42)
    for ring_r in [160, 120, 80]:
        draw.ellipse([cx - ring_r, cy - ring_r, cx + ring_r, cy + ring_r], outline=(255, 255, 255), width=2)
    # 钻石切角八边形
    d_size = 90
    diamond = [
        (cx, cy - d_size),
        (cx + d_size * 0.7, cy - d_size * 0.7),
        (cx + d_size, cy),
        (cx + d_size * 0.7, cy + d_size * 0.7),
        (cx, cy + d_size),
        (cx - d_size * 0.7, cy + d_size * 0.7),
        (cx - d_size, cy),
        (cx - d_size * 0.7, cy - d_size * 0.7),
    ]
    draw.polygon(diamond, outline=(255, 215, 0), fill=(255, 255, 255))

    # 4. 顶部装饰栏与 4K 标志
    draw.rectangle([0, 0, w, 60], fill=(0, 0, 0))
    # 金色 4K 胶囊
    draw.rounded_rectangle([30, 16, 150, 44], radius=6, fill=(255, 195, 0))
    # 评分徽章
    draw.rounded_rectangle([w - 120, 16, w - 30, 44], radius=6, fill=(220, 30, 50))

    # 5. 底部暗夜阴影遮罩（为剧名文字提供高对比度）
    for y in range(int(h * 0.65), h):
        factor = (y - h * 0.65) / (h * 0.35)
        dark_r = int(10 * factor)
        dark_g = int(10 * factor)
        dark_b = int(15 * factor)
        draw.line([(0, y), (w, y)], fill=(dark_r, dark_g, dark_b))

    # 6. 保存为高质量 PNG
    out_path = os.path.join(POSTERS_DIR, f"poster_{index + 1}.png")
    img.save(out_path, format="PNG")
    print(f"Generated {out_path} ({title})")

def main():
    for i, drama in enumerate(DRAMAS):
        draw_poster(i, drama[0], drama[1], drama[2], drama[3], drama[4])
    print(f"Successfully generated all {len(DRAMAS)} HD movie posters!")

if __name__ == "__main__":
    main()
