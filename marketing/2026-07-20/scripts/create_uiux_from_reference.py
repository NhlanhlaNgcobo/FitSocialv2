from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import math

ROOT = Path(r"C:\Users\user\Desktop\Fitsocial")
OUT = ROOT / "marketing" / "fitsocial_uiux_reference"
OUT.mkdir(parents=True, exist_ok=True)
SRC = Path(r"C:\Users\user\AppData\Local\Temp")
grid = Image.open(SRC / "codex-clipboard-b1965a8e-6fee-4c03-aa68-88dbbf4a23ce.png").convert("RGB")
hero = Image.open(SRC / "codex-clipboard-4f636193-c2f0-4ee6-8e86-bfc08433c593.png").convert("RGB")
FONT_DIR = Path(r"C:\Windows\Fonts")
def font(size, bold=False):
    return ImageFont.truetype(str(FONT_DIR / ("Arialbd.ttf" if bold else "Arial.ttf")), size)
ORANGE=(255,107,26); WHITE=(248,248,248); MUTED=(166,160,156); BLACK=(5,5,5); PANEL=(17,17,17)
boxes=[(28,18,285,535),(299,18,558,535),(570,18,830,535),(846,18,1104,535),(1122,18,1390,535),(28,575,285,1092),(299,575,558,1092),(570,575,830,1092),(846,575,1104,1092),(1122,575,1390,1092)]
captions=[
    ("Meet your new routine.","Train. Fuel. Share. Grow.","Start with a fitness community built around your real life."),
    ("Make your first move.","Simple onboarding. Clear goals.","Create an account and get your plan moving."),
    ("Progress is better together.","Your community feed.","Share the run, the meal, and the small win."),
    ("One tap starts the work.","Log workouts, runs, meals, and posts.","Your daily actions, organised in one place."),
    ("Make meals count.","Snap. Log. Keep going.","Turn everyday food into useful nutrition data."),
    ("Know what is on your plate.","Calories and macros, made practical.","Save meals you want to repeat."),
    ("Train with structure.","Every set has a purpose.","Track the work and share the win."),
    ("Your journey, your profile.","Show the work behind the result.","Keep goals, activity, and community in one view."),
    ("See the trend.","Progress you can feel and measure.","Workouts, calories burned, and active minutes."),
    ("Celebrate consistency.","Achievements that feel earned.","Build streaks, collect badges, and keep moving."),
]
def make_phone(src):
    pix=src.load(); corner=pix[0,0]; out=Image.new("RGBA",src.size,(0,0,0,0)); op=out.load()
    for y in range(src.height):
        for x in range(src.width):
            r,g,b=pix[x,y]; dist=math.sqrt((r-corner[0])**2+(g-corner[1])**2+(b-corner[2])**2)
            op[x,y]=(r,g,b,0 if dist<28 and min(r,g,b)>170 else 255)
    return out
phones=[make_phone(grid.crop(b)) for b in boxes]
def poster(no,title,sub,body,idxs,layout):
    im=Image.new("RGB",(1080,1350),BLACK); d=ImageDraw.Draw(im)
    d.ellipse((760,-180,1260,360),fill=(74,29,12)); d.ellipse((-260,1110,330,1620),fill=(43,20,12))
    d.text((72,66),"Fit",font=font(28,True),fill=WHITE); d.text((125,66),"Social",font=font(28,True),fill=ORANGE)
    d.text((72,154),f"UI/UX  {no:02d}/20",font=font(14,True),fill=ORANGE); d.text((72,215),title,font=font(45,True),fill=WHITE)
    d.text((72,285),sub,font=font(22,True),fill=ORANGE); d.multiline_text((72,360),body,font=font(18),fill=MUTED,spacing=8)
    if layout=="hero":
        card=hero.resize((930,620),Image.Resampling.LANCZOS); im.paste(card,(75,585))
    elif layout=="duo":
        for pos,idx in zip([(115,610),(535,610)],idxs):
            p=phones[idx].resize((360,720),Image.Resampling.LANCZOS); im.paste(p,pos,p)
    elif layout=="trio":
        for pos,idx in zip([(58,620),(365,620),(672,620)],idxs):
            p=phones[idx].resize((295,590),Image.Resampling.LANCZOS); im.paste(p,pos,p)
    else:
        p=phones[idxs[0]].resize((510,1025),Image.Resampling.LANCZOS); glow=Image.new("RGBA",(1080,1350),(0,0,0,0)); gd=ImageDraw.Draw(glow); gd.ellipse((470,1100,1030,1450),fill=(255,80,0,75)); glow=glow.filter(ImageFilter.GaussianBlur(60)); im=Image.alpha_composite(im.convert("RGBA"),glow).convert("RGB"); im.paste(p,(500,530),p)
    d=ImageDraw.Draw(im); d.text((72,1240),"Train. Fuel. Share. Grow.",font=font(15,True),fill=WHITE); d.text((72,1280),"FitSocial · South Africa",font=font(12),fill=MUTED); im.save(OUT/f"fitsocial_uiux_ref_{no:02d}.jpg",quality=95,optimize=True)
for i,(title,sub,body) in enumerate(captions,1):
    layout="hero" if i==3 else ("duo" if i in (4,7,10) else ("trio" if i in (6,8) else "single")); poster(i,title,sub,body,[(i-1)%10,i%10,(i+1)%10],layout)
for j,(title,sub,body) in enumerate(captions,11):
    layout="hero" if j==15 else ("duo" if j in (13,17,19) else ("trio" if j in (12,16,20) else "single")); poster(j,title,sub,body,[(j-1)%10,j%10,(j+1)%10],layout)
print(f"Created 20 reference-based UI/UX images in {OUT}")
