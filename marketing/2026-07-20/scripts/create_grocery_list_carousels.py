from pathlib import Path
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from create_marketing_carousels import OUT, W, H, ORANGE, WHITE, MUTED, SURFACE, SURFACE_HIGH, STROKE, font, fit_bg, gradient_overlay, brand


ROOT = Path(r"C:\Users\user\Desktop\Fitsocial")
LOGOS = ROOT / "marketing" / "logos"

BACKGROUND_SOURCES = [
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-99dd93ef-a6f8-4fc0-aca1-e52e729c3f62.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-ada223ca-fc8c-43fa-b88e-70197a53a726.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-9758a456-cc43-4e72-b807-1ef0e5ae6931.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-d0079e08-ccd2-41ab-8274-e6b0a9efc4a6.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-0e661f2c-df38-481b-adc4-a86265ea91e5.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-656b693a-9971-4a70-8169-05777f67bf08.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-35292ec2-a1e6-4b1d-90c9-0a914dee6c09.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-9e5acd6b-2330-4aa2-a1c9-06e8516670ab.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-244ebd81-d0d6-499b-a942-c6432dc02eab.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7690bf84-1b98-4f5f-aa18-7129fd32a55f.png",
]

STORE_LOGOS = {
    "Woolworths": LOGOS / "woolworths.png",
    "Checkers": LOGOS / "checkers.png",
    "Pick n Pay": LOGOS / "picknpay.png",
    "Shoprite": LOGOS / "shoprite.png",
}


def plan(store, title, subtitle, servings, budget, protein, carbs, produce, extras):
    return {
        "store": store,
        "title": title,
        "subtitle": subtitle,
        "servings": servings,
        "budget": budget,
        "protein": protein,
        "carbs": carbs,
        "produce": produce,
        "extras": extras,
    }


PLANS = [
    plan("Woolworths", "Woolies student lean bulk", "Affordable staples with a high-protein finish.", "10 meals", "Budget-conscious", "Chicken portions · eggs · plain yoghurt", "Oats · rice · wholewheat wraps", "Bananas · spinach · frozen veg", "Peanut butter · milk · spices"),
    plan("Woolworths", "Working week weight loss", "Prep balanced lunches before the Monday rush.", "10 lunches", "Simple + structured", "Chicken breast · tuna · lentils", "Sweet potato · brown rice", "Greens · cucumber · apples", "Low-fat yoghurt · lemon · herbs"),
    plan("Woolworths", "HYROX fuel week", "Carbs for the engine. Protein for recovery.", "14 meals", "Performance prep", "Chicken · lean mince · eggs", "Rice · oats · potatoes", "Bananas · berries · broccoli", "Milk · yoghurt · electrolyte sachets"),
    plan("Woolworths", "Vegetarian budget prep", "A plant-forward plan for busy Durban weeks.", "12 meals", "Low-waste", "Beans · lentils · eggs", "Rice · oats · wholewheat bread", "Cabbage · carrots · spinach", "Peanut butter · hummus · tomatoes"),
    plan("Woolworths", "Family strength prep", "Big-batch meals that keep the whole house ready.", "20 portions", "Batch cooking", "Chicken · lean mince · eggs", "Rice · pasta · potatoes", "Mixed vegetables · onions · fruit", "Milk · cheese · tomato relish"),
    plan("Checkers", "Student saver meal prep", "A practical starter shop for campus life.", "10 meals", "Student-friendly", "Eggs · chicken livers · beans", "Rice · oats · brown bread", "Cabbage · frozen veg · bananas", "Peanut butter · milk · stock cubes"),
    plan("Checkers", "7-day weight loss basics", "Repeatable meals without complicated rules.", "14 meals", "Lean + filling", "Chicken · tuna · beans", "Potatoes · oats · brown rice", "Spinach · tomatoes · apples", "Plain yoghurt · herbs · lemon"),
    plan("Checkers", "HYROX training prep", "Fuel the runs, stations, and recovery days.", "14 meals", "Race week", "Chicken · lean mince · eggs", "Rice · oats · wraps", "Bananas · carrots · broccoli", "Yoghurt · milk · electrolytes"),
    plan("Checkers", "Office lunch plan", "Pack it once and stop buying lunch every day.", "10 lunches", "Workweek", "Chicken · tuna · eggs", "Rice · wraps · potatoes", "Salad greens · cucumber · fruit", "Hummus · yoghurt · chilli"),
    plan("Checkers", "High-protein bulk", "A straightforward surplus for strength training.", "15 meals", "Calorie surplus", "Chicken · mince · eggs · yoghurt", "Rice · pasta · oats · bread", "Bananas · avocado · frozen veg", "Peanut butter · milk · olive oil"),
    plan("Pick n Pay", "Campus bulk on a budget", "Eat enough without emptying your wallet.", "12 meals", "Rands-aware", "Eggs · chicken · baked beans", "Rice · oats · potatoes", "Cabbage · carrots · bananas", "Peanut butter · milk · spices"),
    plan("Pick n Pay", "Lean cut grocery list", "High-volume food for a focused week.", "14 meals", "Lean plan", "Chicken · tuna · lentils", "Sweet potato · oats", "Greens · cucumber · berries", "Low-fat yoghurt · herbs · lemon"),
    plan("Pick n Pay", "Budget bulk basics", "Build meals around staples you can repeat.", "15 meals", "Bulk prep", "Chicken · eggs · mince", "Rice · pasta · oats", "Frozen vegetables · bananas", "Milk · peanut butter · cheese"),
    plan("Pick n Pay", "Meat-free prep", "Affordable plant-based structure for the week.", "12 meals", "Vegetarian", "Beans · lentils · eggs", "Rice · oats · bread", "Cabbage · spinach · tomatoes", "Hummus · peanut butter · yoghurt"),
    plan("Pick n Pay", "HYROX race-week shop", "Practice the fuel before race day.", "10 meals", "Performance", "Chicken · eggs · tuna", "Rice · oats · wraps", "Bananas · oranges · vegetables", "Yoghurt · milk · electrolyte sachets"),
    plan("Shoprite", "Student bulk starter", "Simple calories for a full training timetable.", "12 meals", "Value shop", "Eggs · chicken livers · beans", "Rice · oats · bread", "Cabbage · onions · bananas", "Peanut butter · milk · spices"),
    plan("Shoprite", "Weight loss on basics", "Keep it simple, filling, and trackable.", "14 meals", "Value lean plan", "Chicken · eggs · beans", "Potatoes · oats · rice", "Frozen veg · spinach · apples", "Plain yoghurt · lemon · herbs"),
    plan("Shoprite", "Working lunch batch", "Cook Sunday. Pack Monday to Friday.", "10 lunches", "Workweek value", "Chicken · tuna · eggs", "Rice · potatoes · wraps", "Carrots · cucumber · fruit", "Hummus · yoghurt · chilli"),
    plan("Shoprite", "Family budget prep", "Big pots, simple ingredients, less waste.", "20 portions", "Family value", "Chicken · mince · beans", "Rice · pasta · potatoes", "Cabbage · carrots · onions", "Tomato sauce · stock · spices"),
    plan("Shoprite", "Recovery week shop", "Refuel after hard sessions without overcomplicating it.", "12 meals", "Recovery", "Chicken · eggs · yoghurt", "Rice · oats · potatoes", "Bananas · vegetables · fruit", "Milk · peanut butter · water"),
]


def paste_logo(canvas, store, box):
    path = STORE_LOGOS[store]
    logo = Image.open(path).convert("RGBA")
    max_w, max_h = box[2] - box[0], box[3] - box[1]
    logo.thumbnail((max_w, max_h), Image.Resampling.LANCZOS)
    x = box[0] + (max_w - logo.width) // 2
    y = box[1] + (max_h - logo.height) // 2
    canvas.alpha_composite(logo, (x, y))


def grocery_panel(img, item, slide_number):
    draw = ImageDraw.Draw(img)
    x1, y1, x2, y2 = (52, 550, 1028, 1250)
    draw.rounded_rectangle((x1, y1, x2, y2), radius=34, fill=(5, 5, 5, 242), outline=STROKE, width=3)
    # Store badge and FitSocial co-branding
    draw.rounded_rectangle((x1 + 24, y1 + 22, x1 + 216, y1 + 90), radius=18, fill=(247, 247, 247, 245))
    paste_logo(img, item["store"], (x1 + 38, y1 + 31, x1 + 202, y1 + 81))
    draw.text((x1 + 242, y1 + 36), "GROCERY LIST", font=font(18, bold=True), fill=ORANGE)
    draw.text((x2 - 150, y1 + 36), f"{slide_number:02d}/20", font=font(18, bold=True), fill=MUTED)
    draw.text((x1 + 26, y1 + 116), item["store"], font=font(15, bold=True), fill=MUTED)
    draw.text((x1 + 26, y1 + 145), item["title"], font=font(30, bold=True), fill=WHITE)
    draw.text((x1 + 26, y1 + 188), item["subtitle"], font=font(17), fill=MUTED)
    draw.line((x1 + 26, y1 + 224, x2 - 26, y1 + 224), fill=STROKE, width=2)
    columns = [
        ("PROTEIN", item["protein"], x1 + 26),
        ("CARBS", item["carbs"], x1 + 500),
        ("PRODUCE", item["produce"], x1 + 26),
        ("EXTRAS", item["extras"], x1 + 500),
    ]
    ys = [y1 + 252, y1 + 252, y1 + 410, y1 + 410]
    for (label, value, x), y in zip(columns, ys):
        draw.text((x, y), label, font=font(15, bold=True), fill=ORANGE)
        lines = value.split(" · ")
        for index, line in enumerate(lines):
            draw.ellipse((x, y + 38 + index * 25, x + 8, y + 46 + index * 25), fill=ORANGE)
            draw.text((x + 18, y + 31 + index * 25), line, font=font(17), fill=WHITE)
    draw.text((x1 + 26, y2 - 52), f"{item['servings']}  •  {item['budget']}  •  Prices vary by store and location", font=font(14, bold=True), fill=MUTED)


def make_slide(index, item):
    source = BACKGROUND_SOURCES[(index - 1) % len(BACKGROUND_SOURCES)]
    img = fit_bg(source)
    gradient_overlay(img)
    brand(ImageDraw.Draw(img))
    draw = ImageDraw.Draw(img)
    draw.text((64, 168), "FITSOCIAL MEAL PREP", font=font(19, bold=True), fill=ORANGE)
    draw.text((64, 215), "Shop smart.\nPrep with purpose.", font=font(62, bold=True), fill=WHITE, spacing=4)
    grocery_panel(img, item, index)
    draw.text((64, H - 42), "TRAIN. FUEL. SHARE. GROW.", font=font(15, bold=True), fill=MUTED)
    img.convert("RGB").save(OUT / f"fitsocial_grocery_{index:02d}.jpg", quality=95, optimize=True)


def main():
    for index, item in enumerate(PLANS, start=1):
        make_slide(index, item)


if __name__ == "__main__":
    main()
