from pathlib import Path
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from create_marketing_carousels import OUT, W, H, ORANGE, MUTED, font, fit_bg, gradient_overlay, brand, title_block, phone_card


SOURCES = [
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-defebaae-76e4-487f-afa5-c7c1d5b8e977.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-ae3ef576-5bc1-4240-93a5-0a745e977e2f.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-dd0d4ca2-a546-4128-bb44-f3c0ff2b4ca3.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-c9d8631b-80f1-450b-a872-4857b9193ec4.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-d289db59-9288-4d4d-a474-b248773d3711.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-04cbd04f-9717-4d09-bb12-7681594148b4.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-fa647e27-e436-4fa7-a51b-415e2661add9.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7b67ed2a-6d30-4c9e-96ba-0827c7d91416.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-425130e4-47f2-4f6d-84a8-b444ad5ceb68.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-de4a84cb-d88e-406b-959d-c6dd577416dc.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7177a7d8-1777-4a45-8754-ec4cb683b496.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-c8822af8-6c57-43cf-97d9-5ab8e952a998.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-1070cc48-8d3a-4b5f-83fc-e5d3fd307718.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-8530ec13-d3c7-4e7a-93f4-91f06aab3da0.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-4845987f-f1f7-4cb7-9acd-afead22fe728.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-4fa2041d-59c9-4438-9424-6e3ecec03308.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-6ad89208-2e3c-4d1c-80d9-8b54fdb1cd44.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-46baf672-cc5c-4a03-983d-2bb8ded8c999.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-4260e733-fddc-407c-850b-d7b192ab01e9.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-28239114-8011-43a8-b628-93106e8d911c.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7dd27c32-1106-4b08-89dd-c80407a5a17c.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-0927bf72-cdc0-4610-94ec-78cce569f8c8.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-fa096c20-6a58-4a6e-8b13-b3421543eb40.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-a7a9502b-94d2-432a-a0b8-dc83108c4e93.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-9e91107d-6cfa-4330-ab2b-9033c598bbfe.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-daf4996b-f2de-4002-a559-7ef64bb2f5cb.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-be7c3e44-3157-4172-ac4b-460e5cc3d851.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-e2c4680e-0458-4bce-a4ea-2aea5d99a42a.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-3c8f8414-c67b-480b-b973-f3da1031e0cd.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-33e1f7d3-e614-4c65-a66e-9fbe103d3739.png",
]


COPY = [
    ("HYROX TRAINING", "HYROX is built in the basics.", "Run. Push. Pull. Repeat.", "Race prep", [("Run", "1 km"), ("Push", "20 m"), ("Repeat", "08x")]),
    ("HYROX TRAINING", "Train the stations.", "Break the race into repeatable pieces.", "Stations", [("Sled", "40 kg"), ("Row", "500 m"), ("Lunges", "20 m")]),
    ("HYROX TRAINING", "Build engine + strength.", "Your best race needs both.", "Hybrid session", [("Run", "4 km"), ("Strength", "03"), ("Time", "52 min")]),
    ("HYROX TRAINING", "Practice transitions.", "Smooth changes save energy when it counts.", "Race strategy", [("Transitions", "06"), ("Pace", "Steady"), ("Focus", "High")]),
    ("HYROX TRAINING", "Keep your pace honest.", "Start controlled. Finish powerful.", "Run log", [("Distance", "5 km"), ("Pace", "5:30/km"), ("Effort", "08/10")]),
    ("HYROX TRAINING", "Carry strong.", "Train your grip, core, and confidence.", "Strength log", [("Carry", "80 m"), ("Grip", "Strong"), ("Rounds", "04")]),
    ("HYROX TRAINING", "Run the work.", "Every station is a chance to build your engine.", "Workout", [("Calories", "540"), ("Stations", "08"), ("Time", "48 min")]),
    ("HYROX TRAINING", "Train with your crew.", "Accountability makes hard sessions easier to start.", "Team session", [("Athletes", "04"), ("Rounds", "06"), ("Support", "+100%")]),
    ("DURBAN TO THE FINISH", "KZN to the finish line.", "Build your hybrid fitness one session at a time.", "Progress", [("Workouts", "04"), ("Runs", "03"), ("Streak", "14 days")]),
    ("HYROX RECOVERY", "Recover like it matters.", "The next session starts with what you do after this one.", "Recovery", [("Water", "2.4 L"), ("Sleep", "07 h"), ("Fuel", "On track")]),
    ("BUDGET MEAL PREP", "Eat well on a student budget.", "Simple staples. Stronger habits.", "Budget plate", [("Cost", "Low"), ("Protein", "32 g"), ("Meals", "04")]),
    ("BUDGET MEAL PREP", "Staples do the heavy lifting.", "Rice, beans, eggs, vegetables, and consistency.", "Meal prep", [("Meals", "05"), ("Protein", "36 g"), ("Prep", "Sunday")]),
    ("BUDGET MEAL PREP", "Prep once. Save all week.", "Make your rand work harder for your goals.", "Weekly prep", [("Containers", "08"), ("Cost", "R320"), ("Days", "05")]),
    ("BUDGET MEAL PREP", "Make your rand work harder.", "Affordable fuel can still be purposeful fuel.", "Shopping list", [("Staples", "06"), ("Budget", "R400"), ("Meals", "12")]),
    ("STUDENT MEAL PREP", "The student meal plan.", "Pack it before class. Stay ready after class.", "Packed lunch", [("Calories", "620"), ("Protein", "35 g"), ("Cost", "R35")]),
    ("BUDGET MEAL PREP", "Protein without the premium price.", "Eggs, beans, chicken, and smart portions add up.", "Protein", [("Protein", "42 g"), ("Cost", "R38"), ("Prep", "15 min")]),
    ("STUDENT MEAL PREP", "Pack it before class.", "A prepared meal beats an expensive impulse buy.", "Student day", [("Breakfast", "Ready"), ("Lunch", "Packed"), ("Water", "1 L")]),
    ("COMMUNITY MEAL PREP", "Cook together. Save together.", "Healthy habits are easier when the kitchen is shared.", "Shared prep", [("Friends", "04"), ("Meals", "16"), ("Saved", "R240")]),
    ("BUDGET MEAL PREP", "Track the plate, not perfection.", "Awareness is the first step toward consistency.", "Meal review", [("Calories", "580"), ("Protein", "31 g"), ("On plan", "Yes")]),
    ("BUDGET MEAL PREP", "Budget fuel, consistent progress.", "Small choices create a plan you can actually repeat.", "Weekly fuel", [("Meals", "14"), ("Budget", "R420"), ("Streak", "09 days")]),
    ("WEIGHT LOSS PLAN", "Weight loss needs a plan, not punishment.", "Choose habits you can repeat through real life.", "Plan", [("Walks", "04"), ("Meals", "18"), ("Progress", "Steady")]),
    ("WEIGHT LOSS PLAN", "Walk more. Track it.", "Build momentum with movement that fits your day.", "Movement", [("Steps", "9.2K"), ("Walk", "45 min"), ("Streak", "06 days")]),
    ("WEIGHT LOSS PLAN", "Portion awareness wins.", "Track what you eat without losing your joy in food.", "Meal review", [("Calories", "520"), ("Protein", "34 g"), ("Balance", "Good")]),
    ("WEIGHT LOSS PLAN", "Progress you can repeat.", "The best plan is the one you can keep showing up for.", "Progress", [("Weeks", "04"), ("Workouts", "16"), ("Trend", "Down")]),
    ("DURBAN CONSISTENCY", "Stay consistent in Durban heat.", "Hydrate, move, fuel, and keep your goals visible.", "Daily habits", [("Water", "2.5 L"), ("Steps", "10K"), ("Meals", "On plan")]),
    ("LEAN BULK PLAN", "Build with intention.", "Train hard, eat enough, and track the details.", "Bulk plan", [("Calories", "+320"), ("Protein", "145 g"), ("Lifts", "05")]),
    ("LEAN BULK PLAN", "Protein. Calories. Consistency.", "The basics build the body you are working toward.", "Daily target", [("Protein", "150 g"), ("Calories", "2,850"), ("Meals", "05")]),
    ("LEAN BULK PLAN", "Train hard. Eat enough.", "A stronger body needs a stronger routine.", "Strength", [("Sets", "18"), ("Protein", "On target"), ("Sleep", "08 h")]),
    ("LEAN BULK PLAN", "Bulk on a plan.", "Add quality calories without losing structure.", "Meal prep", [("Calories", "2,900"), ("Meals", "05"), ("Progress", "+")]),
    ("KZN STRONG", "KZN strong, one session at a time.", "Train, fuel, track, and grow with your community.", "FitSocial", [("Train", "04"), ("Fuel", "20"), ("Connect", "∞")]),
]


def make_slide(index, source, eyebrow, title, subtitle, card_title, metrics):
    img = fit_bg(Path(source))
    gradient_overlay(img)
    draw = ImageDraw.Draw(img)
    brand(draw)
    title_block(draw, eyebrow, title, subtitle)
    box = (600, 700, 1016, 1230) if index % 2 else (64, 720, 480, 1230)
    phone_card(draw, box, card_title, metrics)
    draw.text((64, H - 78), "TRAIN. FUEL. SHARE. GROW.", font=font(17, bold=True), fill=MUTED)
    draw.text((W - 125, H - 82), f"{index:02d}/55", font=font(20, bold=True), fill=ORANGE)
    img.convert("RGB").save(OUT / f"fitsocial_carousel_{index:02d}.jpg", quality=95, optimize=True)


def main():
    assert len(SOURCES) == 30 and len(COPY) == 30
    for index, (source, copy) in enumerate(zip(SOURCES, COPY), start=26):
        make_slide(index, source, *copy)


if __name__ == "__main__":
    main()
