from PIL import Image, ImageDraw, ImageFont
from pathlib import Path
import textwrap

ROOT = Path(r"C:\Users\user\Desktop\Fitsocial")
OUT = ROOT / "marketing" / "fitsocial_uiux"
OUT.mkdir(parents=True, exist_ok=True)

FONT_DIR = Path(r"C:\Windows\Fonts")
REG = FONT_DIR / "Arial.ttf"
BOLD = FONT_DIR / "Arialbd.ttf"

def font(size, bold=False):
    return ImageFont.truetype(str(BOLD if bold else REG), size)

ORANGE = (255, 107, 26)
WHITE = (247, 247, 247)
MUTED = (166, 160, 156)
BLACK = (5, 5, 5)
SURFACE = (17, 17, 17)
HIGH = (27, 27, 27)
STROKE = (53, 53, 53)
GREEN = (91, 202, 135)

screens = [
    ("01", "WELCOME", "Your strongest routine starts together.", "A simple daily rhythm for training, food, and community.", "GET STARTED", "Welcome to FitSocial", "Train. Fuel. Share. Grow."),
    ("02", "ONBOARDING", "Choose your next level.", "Set a goal that feels personal, measurable, and yours.", "CONTINUE", "What are you working towards?", "Weight loss  •  Strength  •  HYROX"),
    ("03", "HOME", "Your day, in one view.", "See the next action, your streak, and the people keeping pace.", "LOG TODAY", "Good morning, Thando", "TODAY'S RHYTHM"),
    ("04", "DASHBOARD", "Momentum is visible.", "A focused dashboard turns small actions into a bigger picture.", "VIEW PROGRESS", "Weekly momentum", "4 workouts  •  12 meals  •  7 day streak"),
    ("05", "WORKOUTS", "Train with intention.", "Browse sessions by goal, equipment, level, or available time.", "BROWSE WORKOUTS", "Discover workouts", "Strength  •  Conditioning  •  Running"),
    ("06", "WORKOUT DETAIL", "Know exactly what to do.", "Clear sets, reps, rest, and coaching cues remove decision fatigue.", "START WORKOUT", "Lower body strength", "45 min  •  Intermediate  •  Gym"),
    ("07", "ACTIVE SESSION", "One rep at a time.", "Keep the session moving with a clean, low-friction workout view.", "COMPLETE SET", "Barbell back squat", "SET 3 OF 4  •  8 REPS  •  90 SEC REST"),
    ("08", "HYROX", "Train for the full race.", "Build a plan around stations, running, transitions, and race-day confidence.", "VIEW HYROX PLAN", "HYROX prep", "SkiErg  •  Sled push  •  Burpee broad jumps"),
    ("09", "RUN TRACKER", "Every kilometre counts.", "Log outdoor runs, treadmill sessions, pace, distance, and effort.", "LOG RUN", "Saturday 5K", "5.00 km  •  31:42  •  Easy effort"),
    ("10", "MEALS", "Fuel the work.", "Make meal logging feel practical, visual, and easy to repeat.", "LOG A MEAL", "What did you eat?", "Breakfast  •  Lunch  •  Dinner  •  Snacks"),
    ("11", "MEAL DETAIL", "Understand your plate.", "See calories and macros without losing sight of the actual food.", "SAVE MEAL", "Chicken rice bowl", "620 kcal  •  42g protein  •  68g carbs"),
    ("12", "FOOD SCAN", "Log it in seconds.", "Search, scan, or describe a meal and keep your nutrition history moving.", "ADD TO DIARY", "Quick meal log", "Chicken  •  pap  •  chakalaka  •  salad"),
    ("13", "GROCERY PLAN", "Shop with a plan.", "Turn your goal into a simple, affordable list you can actually use.", "VIEW LIST", "Student budget", "Eggs  •  beans  •  rice  •  cabbage  •  chicken"),
    ("14", "MEAL PLAN", "Consistency starts before the week.", "Choose a plan built around your budget, schedule, and goal.", "CHOOSE PLAN", "Working week", "10 packed lunches  •  High protein  •  Simple prep"),
    ("15", "PROGRESS", "See the trend, not one day.", "Track body metrics, performance, habits, and the wins between milestones.", "VIEW INSIGHTS", "Your progress", "Weight trend  ↓  2.4 kg  •  Strength  ↑  18%"),
    ("16", "STREAKS", "Show up for yourself.", "Gentle accountability makes consistency feel rewarding, not punishing.", "KEEP STREAK", "7 day streak", "Train  ✓  Fuel  ✓  Connect  ✓"),
    ("17", "COMMUNITY", "Find your people.", "Join circles that match your goal, pace, and energy.", "EXPLORE CIRCLES", "Your community", "HYROX crew  •  First 5K  •  Stronger together"),
    ("18", "SHARE", "Make progress social.", "Celebrate completed sessions, personal bests, and the effort nobody saw.", "SHARE WIN", "New personal best", "5K complete  •  31:42  •  Keep showing up"),
    ("19", "CHECK-IN", "Reflect, then reset.", "A quick check-in keeps your plan realistic as life changes.", "SAVE CHECK-IN", "How are you feeling?", "Energy  4/5  •  Recovery  3/5  •  Ready to train"),
    ("20", "PROFILE", "Your journey, your data.", "Keep goals, plans, achievements, and preferences in one place.", "EDIT PROFILE", "Thando M.", "Strength goal  •  3 sessions/week  •  South Africa"),
]

def rounded(draw, xy, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)

def draw_wrapped(draw, text, xy, width, fnt, fill, spacing=5):
    words = textwrap.wrap(text, width=width)
    draw.multiline_text(xy, "\n".join(words), font=fnt, fill=fill, spacing=spacing)

def phone_screen(draw, box, title, subtitle, footer, idx):
    x0, y0, x1, y1 = box
    rounded(draw, box, 36, (10,10,10), (68,68,68), 3)
    rounded(draw, (x0+16,y0+18,x1-16,y1-18), 25, SURFACE)
    draw.rectangle((x0+16,y0+18,x1-16,y0+92), fill=(23,23,23))
    draw.ellipse((x0+104,y0+28,x0+160,y0+46), fill=(3,3,3))
    draw.text((x0+34,y0+50), "9:41", font=font(12, True), fill=WHITE)
    draw.text((x1-83,y0+50), "●  ▮", font=font(11, True), fill=WHITE)
    draw.text((x0+35,y0+117), "Fit", font=font(20, True), fill=WHITE)
    draw.text((x0+66,y0+117), "Social", font=font(20, True), fill=ORANGE)
    draw.text((x0+35,y0+160), title, font=font(23, True), fill=WHITE)
    draw_wrapped(draw, subtitle, (x0+35,y0+197), 28, font(13), MUTED, 3)
    # Main visual card: switches between chart, ring, list and community cards.
    content_top = y0+272
    if idx in {1, 15, 16}:
        rounded(draw, (x0+35,content_top,x1-35,content_top+165), 18, HIGH, STROKE)
        draw.ellipse((x0+58,content_top+25,x0+158,content_top+125), outline=ORANGE, width=9)
        draw.arc((x0+58,content_top+25,x0+158,content_top+125), 20, 260, fill=GREEN, width=9)
        draw.text((x0+180,content_top+51), "72%", font=font(29, True), fill=WHITE)
        draw.text((x0+180,content_top+90), "on track", font=font(12), fill=MUTED)
    elif idx in {4, 9, 14}:
        rounded(draw, (x0+35,content_top,x1-35,content_top+165), 18, HIGH, STROKE)
        for i, h in enumerate([45, 70, 58, 102, 84, 125, 145]):
            xx=x0+60+i*38
            draw.rounded_rectangle((xx,content_top+142-h,xx+18,content_top+142), radius=6, fill=ORANGE if i==6 else (117,55,29))
        draw.text((x0+57,content_top+24), "This week", font=font(12), fill=MUTED)
    else:
        for i, label in enumerate(["Today’s focus", "Your next action", "Community update"]):
            yy=content_top+i*64
            rounded(draw, (x0+35,yy,x1-35,yy+48), 13, HIGH, STROKE)
            draw.ellipse((x0+51,yy+14,x0+66,yy+29), fill=ORANGE if i==0 else GREEN)
            draw.text((x0+80,yy+12), label, font=font(12, True), fill=WHITE)
            draw.text((x0+80,yy+29), "Tap to explore", font=font(10), fill=MUTED)
    rounded(draw, (x0+35,y1-103,x1-35,y1-62), 20, ORANGE)
    draw.text((x0+72,y1-92), footer, font=font(12, True), fill=BLACK)
    for i, label in enumerate(["Home", "Train", "Fuel", "Circle"]):
        draw.text((x0+43+i*70,y1-43), label, font=font(9, True if i==0 else False), fill=ORANGE if i==0 else MUTED)

for no, section, headline, body, cta, phone_title, phone_subtitle in screens:
    canvas = Image.new("RGB", (1080,1350), BLACK)
    d = ImageDraw.Draw(canvas)
    # warm orange glow
    d.ellipse((720,-220,1280,330), fill=(75,30,12))
    d.ellipse((-230,1050,340,1580), fill=(45,20,11))
    d.text((72,70), "Fit", font=font(28, True), fill=WHITE)
    d.text((124,70), "Social", font=font(28, True), fill=ORANGE)
    d.text((72,150), section, font=font(17, True), fill=ORANGE)
    draw_wrapped(d, headline, (72,205), 18, font(46, True), WHITE, 2)
    draw_wrapped(d, body, (72,430), 30, font(18), MUTED, 8)
    rounded(d, (72,570,360,625), 28, ORANGE)
    d.text((108,588), cta, font=font(13, True), fill=BLACK)
    d.text((72,1245), "Train. Fuel. Share. Grow.", font=font(15, True), fill=WHITE)
    d.text((72,1280), f"FitSocial UI/UX showcase  ·  {no}/20", font=font(12), fill=MUTED)
    phone_screen(d, (570,105,1010,1210), phone_title, phone_subtitle, cta, int(no))
    canvas.save(OUT / f"fitsocial_uiux_{no}.jpg", quality=95, optimize=True)

print(f"Created {len(screens)} UI/UX showcase images in {OUT}")
