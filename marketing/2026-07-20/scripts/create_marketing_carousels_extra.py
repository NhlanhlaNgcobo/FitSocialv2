from pathlib import Path
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
from create_marketing_carousels import (
    OUT, W, H, BLACK, SURFACE, SURFACE_HIGH, STROKE, ORANGE, WHITE, MUTED,
    font, fit_bg, gradient_overlay, brand, title_block, phone_card, footer,
)


SOURCES = [
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-32b6802e-eff4-48c4-9e87-d21c7c4a2b62.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-313aac29-d083-44da-b0b6-9d2a03c6ec9b.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-e2a27f01-7361-4396-be8d-afd594c79f4f.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-3d5fc62d-00ad-4349-acfb-6a769dfc657f.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-b467a588-a5b9-4044-8559-c7dbd965b059.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-36c1b210-25ac-42a4-ab9a-4cfa6de08fd4.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-5dbdd2ee-b9e3-4eb3-ace0-0b06d1f713dc.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-16de0c79-c4f4-4b60-872d-8037e30ca811.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-fb7d4d92-1db3-42df-aacb-3136d9ec20bf.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-f7973c7c-86ab-441a-a69a-bf8e3cd1e386.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-c91278f2-8664-41c5-b0bd-1dbdbc451ddc.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-8d79fd96-c666-4ac3-a121-da5e48018aa1.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-a8133920-a326-4886-8876-5af5d84ea4e9.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-2a1686b0-c70e-4f7e-8713-1d7eee4a3159.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-ff061cb2-1cf5-47eb-8e9e-c21a5654b828.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-8174bfcb-6a12-4e78-88e7-547a932ef657.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-fa6c6aff-1755-4483-93e7-62266fbeeaf4.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-a709ef87-dc36-49e5-b944-699307df2356.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-b8e03f74-c2a6-4b78-90ad-9ef00f063a86.png",
    r"C:\Users\user\.codex\generated_images\019f7e7d-672f-7812-9c26-82fa04c0cff9\exec-7827b833-17a8-4dc2-8ea9-6d7f531262d8.png",
]

COPY = [
    ("BUILD YOUR CIRCLE", "You don't have to do it alone.", "Find your people. Share the journey.", "Community", [("Members", "1.2K"), ("Check-ins", "84"), ("Streak", "07 days")]),
    ("SHOW UP TOGETHER", "A little accountability goes a long way.", "Encouragement turns good intentions into repeatable habits.", "Accountability", [("Check-ins", "12"), ("Wins shared", "08"), ("Momentum", "+24%")]),
    ("CELEBRATE THE WIN", "Progress feels better when it's shared.", "Celebrate the milestones that keep everyone moving forward.", "Milestones", [("Milestones", "06"), ("Likes", "128"), ("Replies", "24")]),
    ("KEEP IT MOVING", "Your feed, your momentum.", "Turn workouts into conversations and motivation into action.", "Activity feed", [("Posts", "18"), ("Likes", "96"), ("Comments", "31")]),
    ("FIND YOUR PEOPLE", "Move with people who get it.", "Train together. Grow together. Keep showing up.", "Your crew", [("Training", "04"), ("Friends", "09"), ("Streak", "14 days")]),
    ("BETWEEN SESSIONS", "Stay connected between sessions.", "Keep your goals in the conversation, even on rest days.", "Community", [("Updates", "07"), ("Support", "24/7"), ("Next up", "Tomorrow")]),
    ("WORKOUT CONSISTENCY", "Consistency starts with a log.", "Record the session. Come back stronger.", "Log workout", [("Duration", "45 min"), ("Exercises", "06"), ("Calories", "420")]),
    ("MAKE IT VISIBLE", "Make progress visible.", "Track time, calories, exercises, and momentum in one place.", "Progress", [("Workouts", "04"), ("Calories", "1,840"), ("Progress", "+18%")]),
    ("RUN YOUR RACE", "Run your own race.", "Log the distance. Keep the streak moving.", "Log run", [("Distance", "5.0 km"), ("Pace", "5:42/km"), ("Streak", "07 days")]),
    ("RETURN TO THE PLAN", "A plan you can return to.", "Small sessions add up when you keep coming back.", "This week", [("Sessions", "04"), ("Minutes", "180"), ("Goal", "72%")]),
    ("NUTRITION AWARENESS", "Make every meal count.", "Build awareness without losing your rhythm.", "Meal review", [("Calories", "640 kcal"), ("Protein", "42 g"), ("Carbs", "58 g")]),
    ("FUEL THE WORK", "Know what fuels you.", "Track calories and macros in one place.", "Daily fuel", [("Calories", "1,920"), ("Protein", "128 g"), ("Water", "2.1 L")]),
    ("PREPARE TO WIN", "Preparation beats guesswork.", "Plan your meals. Support your training.", "Meal plan", [("Meals", "04"), ("Protein", "On target"), ("Prep", "Sunday")]),
    ("REPEAT THE HABIT", "Consistency tastes like progress.", "Repeat the habits that move you forward.", "Nutrition streak", [("Days", "12"), ("Meals", "36"), ("On target", "89%")]),
    ("FUEL THE WORK", "Fuel the work.", "Your training deserves nutrition you can track.", "After workout", [("Calories", "520 kcal"), ("Protein", "38 g"), ("Recovery", "Ready")]),
    ("SHARE THE TABLE", "Share the table.", "Healthy habits are easier when they're shared.", "Shared meals", [("Meals", "12"), ("Friends", "05"), ("Support", "+31%")]),
    ("ACCOUNTABILITY CREW", "Find your accountability crew.", "Encouragement makes showing up easier.", "Your community", [("Check-ins", "18"), ("Replies", "42"), ("Streak", "21 days")]),
    ("PROGRESS TOGETHER", "Progress is better together.", "Share milestones and motivate the next rep.", "Community feed", [("Milestone", "New PR"), ("Cheers", "64"), ("Next rep", "Today")]),
    ("PART OF THE PLAN", "Your people are part of the plan.", "Connect, check in, keep going.", "Weekly circle", [("Members", "08"), ("Check-ins", "27"), ("Goal", "On track")]),
    ("FITNESS COMMUNITY", "Train. Track. Connect.", "One community for the habits that make you stronger.", "FitSocial", [("Train", "04"), ("Fuel", "12"), ("Connect", "∞")]),
]


def make_slide(index, source, eyebrow, title, subtitle, card_title, metrics):
    img = fit_bg(Path(source))
    gradient_overlay(img)
    draw = ImageDraw.Draw(img)
    brand(draw)
    title_block(draw, eyebrow, title, subtitle)
    # Alternate card position to create a varied but coherent campaign system.
    if index % 2:
        box = (600, 700, 1016, 1230)
    else:
        box = (64, 720, 480, 1230)
    phone_card(draw, box, card_title, metrics)
    draw.text((64, H - 78), "TRAIN. FUEL. SHARE. GROW.", font=font(17, bold=True), fill=MUTED)
    draw.text((W - 125, H - 82), f"{index:02d}/25", font=font(20, bold=True), fill=ORANGE)
    img.convert("RGB").save(OUT / f"fitsocial_carousel_{index:02d}.jpg", quality=95, optimize=True)


def main():
    for index, (source, copy) in enumerate(zip(SOURCES, COPY), start=6):
        make_slide(index, source, *copy)


if __name__ == "__main__":
    main()
