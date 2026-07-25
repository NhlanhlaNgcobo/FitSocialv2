from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter


ROOT = Path(r"C:\Users\user\Desktop\Fitsocial")
OUT = ROOT / "marketing" / "fitsocial_carousel"
OUT.mkdir(parents=True, exist_ok=True)

SOURCES = [
    Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-f311f99b-56ab-4044-a8eb-c0b11b213bbf.png"),
    Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7f3b1a79-d061-4ac0-bc34-a5b98d88b252.png"),
    Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-0a96df80-142f-4405-b9d4-c344f34f8f71.png"),
    Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa082f0520\exec-b83371ee-e200-428b-a45f-9464148ce765.png"),
    Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-22c675bd-6625-4830-9872-fa082f0520f4.png"),
]

# Correct the fourth source path if the generated asset lives in the shared folder.
SOURCES[3] = Path(r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-b83371ee-e200-428b-a45f-9464148ce765.png")

W, H = 1080, 1350
BLACK = "#050505"
SURFACE = "#111111"
SURFACE_HIGH = "#1A1A1A"
STROKE = "#2B2B2B"
ORANGE = "#FF6B1A"
WHITE = "#F7F7F7"
MUTED = "#B1AAA5"

FONT = r"C:\Windows\Fonts\segoeui.ttf"
FONT_BOLD = r"C:\Windows\Fonts\segoeuib.ttf"
FONT_ITALIC = r"C:\Windows\Fonts\segoeuiz.ttf"


def font(size, bold=False, italic=False):
    path = FONT_ITALIC if italic else FONT_BOLD if bold else FONT
    return ImageFont.truetype(path, size)


def fit_bg(path):
    src = Image.open(path).convert("RGB")
    scale = max(W / src.width, H / src.height)
    src = src.resize((int(src.width * scale), int(src.height * scale)), Image.Resampling.LANCZOS)
    left = (src.width - W) // 2
    top = (src.height - H) // 2
    return src.crop((left, top, left + W, top + H)).convert("RGBA")


def rounded(draw, box, radius=26, fill=SURFACE, outline=None, width=2):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def gradient_overlay(img):
    overlay = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    for y in range(H):
        alpha = int(210 * (1 - y / H) + 30)
        d.line((0, y, W, y), fill=(5, 5, 5, alpha))
    img.alpha_composite(overlay)


def brand(draw, x=64, y=58, light=False):
    draw.text((x, y), "Fit", font=font(30, bold=True, italic=True), fill=ORANGE)
    fit_width = draw.textbbox((x, y), "Fit", font=font(30, bold=True, italic=True))[2] - x
    draw.text((x + fit_width - 2, y), "Social", font=font(30, bold=True, italic=True), fill=WHITE if light else WHITE)


def wrap(draw, text, fnt, max_width):
    words = text.split()
    lines, current = [], ""
    for word in words:
        candidate = f"{current} {word}".strip()
        if draw.textbbox((0, 0), candidate, font=fnt)[2] <= max_width:
            current = candidate
        else:
            if current:
                lines.append(current)
            current = word
    if current:
        lines.append(current)
    return lines


def title_block(draw, eyebrow, title, subtitle, y=175, max_width=800):
    draw.text((64, y), eyebrow.upper(), font=font(20, bold=True), fill=ORANGE)
    y += 50
    fnt = font(68, bold=True)
    lines = wrap(draw, title, fnt, max_width)
    for line in lines:
        draw.text((64, y), line, font=fnt, fill=WHITE)
        y += 78
    y += 16
    sf = font(28)
    for line in wrap(draw, subtitle, sf, max_width - 40):
        draw.text((64, y), line, font=sf, fill=MUTED)
        y += 38
    return y


def phone_card(draw, box, heading, metrics, accent=ORANGE):
    x1, y1, x2, y2 = box
    rounded(draw, box, 32, fill=(10, 10, 10, 235), outline=STROKE, width=3)
    draw.rounded_rectangle((x1 + 20, y1 + 18, x2 - 20, y1 + 26), radius=5, fill=STROKE)
    draw.text((x1 + 32, y1 + 58), heading, font=font(25, bold=True), fill=WHITE)
    cy = y1 + 112
    for label, value in metrics:
        rounded(draw, (x1 + 24, cy, x2 - 24, cy + 62), 16, fill=SURFACE_HIGH)
        draw.text((x1 + 40, cy + 13), label, font=font(16), fill=MUTED)
        draw.text((x2 - 190, cy + 10), value, font=font(24, bold=True), fill=accent)
        cy += 76
    rounded(draw, (x1 + 24, y2 - 76, x2 - 24, y2 - 28), 16, fill=accent)
    draw.text((x1 + 50, y2 - 66), "Keep the streak", font=font(18, bold=True), fill=BLACK)


def footer(draw, number):
    draw.text((64, H - 78), "TRAIN. FUEL. SHARE. GROW.", font=font(17, bold=True), fill=MUTED)
    draw.text((W - 110, H - 82), f"0{number}/05", font=font(20, bold=True), fill=ORANGE)


def make_slide(index, source, eyebrow, title, subtitle, card=None, accent_area=None):
    img = fit_bg(source)
    gradient_overlay(img)
    draw = ImageDraw.Draw(img)
    brand(draw)
    title_block(draw, eyebrow, title, subtitle)
    if card:
        phone_card(draw, card[0], card[1], card[2])
    if accent_area:
        x, y, text, value = accent_area
        rounded(draw, (x, y, x + 310, y + 118), 24, fill=(17, 17, 17, 225), outline=ORANGE, width=2)
        draw.text((x + 22, y + 18), text, font=font(16, bold=True), fill=MUTED)
        draw.text((x + 22, y + 48), value, font=font(40, bold=True), fill=ORANGE)
    footer(draw, index)
    img.convert("RGB").save(OUT / f"fitsocial_carousel_{index:02d}.jpg", quality=95, optimize=True)


def main():
    make_slide(
        1, SOURCES[0], "FITNESS, MADE SOCIAL", "Train. Fuel. Share. Grow.",
        "One place to build stronger habits, track your progress, and stay connected to your community.",
        card=((600, 730, 1016, 1230), "Your week", [("Workouts", "04"), ("Meals logged", "12"), ("Progress", "+18%")]),
    )
    make_slide(
        2, SOURCES[1], "BUILD THE HABIT", "Train with a plan.",
        "Log every session, see your momentum, and make consistency visible.",
        card=((590, 700, 1016, 1230), "Log workout", [("Duration", "45 min"), ("Exercises", "06"), ("Calories", "420")]),
    )
    make_slide(
        3, SOURCES[2], "FUEL YOUR GOALS", "Track your diet consistently.",
        "Capture meals, record macros, and keep your nutrition aligned with your training.",
        card=((60, 760, 486, 1230), "Meal review", [("Calories", "640 kcal"), ("Protein", "42 g"), ("Carbs", "58 g")]),
    )
    make_slide(
        4, SOURCES[3], "ACCOUNTABILITY WORKS", "Consistency is easier together.",
        "Share the work, celebrate the wins, and stay motivated with people moving in the same direction.",
        card=((70, 740, 496, 1230), "Community feed", [("Likes", "128"), ("Comments", "24"), ("Streak", "07 days")]),
    )
    make_slide(
        5, SOURCES[4], "YOUR NEXT REP STARTS HERE", "Small actions. Stronger habits.",
        "Log it. Fuel it. Repeat it. Make every day count with FitSocial.",
        card=((590, 740, 1016, 1230), "Your momentum", [("Log", "01"), ("Fuel", "01"), ("Repeat", "∞")]),
    )


if __name__ == "__main__":
    main()
