import math, random, sys
from PIL import Image, ImageDraw, ImageFilter
S = 4096
img = Image.new("RGB", (S, S))
# 背景：上が明るい若草色、下が深い緑のグラデーション
top, bot = (126, 186, 98), (34, 110, 70)
px = img.load()
for y in range(S):
    t = y / S
    c = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
    for x in range(S):
        px[x, y] = c
d = ImageDraw.Draw(img)
cx = S // 2
# 相場のグラフ線（金色、右上がり→少し下がる）
pts = [(560, 1500), (1100, 1180), (1600, 1350), (2200, 820), (2800, 1050), (3540, 640)]
d.line(pts, fill=(255, 214, 102), width=150, joint="curve")
for p in pts:
    d.ellipse([p[0]-120, p[1]-120, p[0]+120, p[1]+120], fill=(255, 214, 102))
# ご飯の山
rice_top = 1700
d.ellipse([cx-1350, rice_top, cx+1350, rice_top+1300], fill=(255, 255, 250))
random.seed(1)
for _ in range(260):
    a = random.uniform(math.pi, 2*math.pi)
    r = random.uniform(0.2, 0.95)
    x = cx + math.cos(a) * 1300 * r
    y = rice_top + 650 + math.sin(a) * 650 * r
    ang = random.uniform(0, 180)
    g = Image.new("L", (160, 90), 0)
    ImageDraw.Draw(g).ellipse([5, 5, 155, 85], fill=255)
    g = g.rotate(ang, expand=True)
    shade = Image.new("RGB", g.size, (236, 232, 220))
    img.paste(shade, (int(x - g.size[0]/2), int(y - g.size[1]/2)), g.point(lambda v: v // 3))
# お茶碗
bowl_y = 2350
d.chord([cx-1550, bowl_y-1250, cx+1550, bowl_y+1250], 0, 180, fill=(196, 52, 40))
d.rectangle([cx-1550, bowl_y-30, cx+1550, bowl_y+60], fill=(196, 52, 40))
d.rounded_rectangle([cx-1600, bowl_y-90, cx+1600, bowl_y+90], radius=90, fill=(222, 78, 60))
d.rounded_rectangle([cx-560, bowl_y+1200, cx+560, bowl_y+1380], radius=60, fill=(150, 36, 28))
# 茶碗の模様（白い帯）
d.arc([cx-1300, bowl_y-900, cx+1300, bowl_y+950], 25, 155, fill=(255, 236, 220), width=70)
img = img.resize((1024, 1024), Image.LANCZOS)
img.save(sys.argv[1])
