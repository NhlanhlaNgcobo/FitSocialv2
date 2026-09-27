"""Lays the real Google map into a shot, under the app's own overlays.

For out/<name>.png with a sidecar out/<name>.maps.json (written by the
harness), fetches a Static Maps image with the exact style, route and camera
the app's GoogleMap would show, and composites it in using the black/white
ground captures as a matte.

    python tool/marketing_shots/mapcomp.py <name> [<name> ...]

The Maps key is read from android/local.properties (MAPS_API_KEY) of this
checkout or the main one, and is never printed.
"""
import hashlib
import io
import json
import math
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
CACHE = HERE / "map_cache"
SCALE = 3  # the shots are captured at 3x


def maps_key():
    candidates = [
        HERE.parents[1] / "android" / "local.properties",
        Path(r"C:\Users\Masibonge Mdlalose\Desktop\Projects\FitSocialv2\fitsocial_app\android\local.properties"),
    ]
    for path in candidates:
        if path.exists():
            for line in path.read_text().splitlines():
                if line.strip().startswith("MAPS_API_KEY"):
                    return line.split("=", 1)[1].strip()
    raise SystemExit("MAPS_API_KEY not found in local.properties")


# --- Web Mercator, in Google's 256-unit world at zoom 0 -------------------

def world(lat, lng):
    siny = min(max(math.sin(math.radians(lat)), -0.9999), 0.9999)
    x = 256 * (0.5 + lng / 360)
    y = 256 * (0.5 - math.log((1 + siny) / (1 - siny)) / (4 * math.pi))
    return x, y


def unworld(x, y):
    lng = (x / 256 - 0.5) * 360
    n = math.pi - 2 * math.pi * y / 256
    lat = math.degrees(math.atan(math.sinh(n)))
    return lat, lng


def camera(entry):
    """(center_lat, center_lng, zoom) for the whole map box."""
    x0, y0, w, h = entry["rect"]
    pl, pt, pr, pb = entry["padding"]
    inner_w, inner_h = w - pl - pr, h - pt - pb
    points = [p for line in entry["polylines"] for p in line["points"]]
    if entry["mode"] == "completed" and len(points) >= 2:
        xs, ys = zip(*(world(*p) for p in points))
        fp = entry["framePadding"]
        span_x, span_y = max(xs) - min(xs), max(ys) - min(ys)
        zoom = min(
            math.log2((inner_w - 2 * fp) / span_x) if span_x else 21,
            math.log2((inner_h - 2 * fp) / span_y) if span_y else 21,
        )
        tx, ty = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
    else:
        zoom = entry["zoom"]
        target = points[-1] if points else entry["target"]
        tx, ty = world(*target)
    # The target sits at the centre of the padded viewport; move the camera so
    # the whole box's centre is where Google would put it.
    k = 2 ** zoom
    dx = (pl + inner_w / 2) - w / 2
    dy = (pt + inner_h / 2) - h / 2
    cx, cy = tx - dx / k, ty - dy / k
    lat, lng = unworld(cx, cy)
    return lat, lng, zoom


def style_params(style_json):
    params = []
    for rule in json.loads(style_json or "[]"):
        parts = []
        if "featureType" in rule:
            parts.append(f"feature:{rule['featureType']}")
        if "elementType" in rule:
            parts.append(f"element:{rule['elementType']}")
        for styler in rule.get("stylers", []):
            for key, value in styler.items():
                if key == "color":
                    value = "0x" + value.lstrip("#")
                parts.append(f"{key}:{value}")
        params.append("|".join(parts))
    return params


OSM = HERE / "osm"

# Road widths in dp at zoom 16, roughly what Google draws.
ROAD_WIDTH = {
    "motorway": 9, "trunk": 9, "primary": 8, "secondary": 7, "tertiary": 6,
    "motorway_link": 5, "trunk_link": 5, "primary_link": 5, "secondary_link": 4.5,
    "residential": 4.5, "unclassified": 4.5, "living_street": 4, "service": 2.5,
    "pedestrian": 3, "footway": 1.5, "path": 1.5, "cycleway": 1.5, "steps": 1.5,
    "track": 1.5,
}
HIGHWAY = {"motorway", "trunk", "motorway_link", "trunk_link"}


def style_colors(style_json):
    """The app's own map colours, read out of its style JSON."""
    colors = {"geometry": "#000000", "landscape": "#0a0a0a", "road": "#1c1c1c",
              "road.highway": "#2b2b2b", "water": "#050505"}
    for rule in json.loads(style_json or "[]"):
        if rule.get("elementType") != "geometry":
            continue
        for styler in rule.get("stylers", []):
            if "color" in styler:
                colors[rule.get("featureType", "geometry")] = styler["color"]
    return colors


def osm_ways(lat, lng):
    for path in OSM.glob("*.json"):
        data = json.loads(path.read_text(encoding="utf-8"))
        ways = [e for e in data["elements"] if e.get("geometry")]
        lats = [p["lat"] for w in ways for p in w["geometry"]]
        lngs = [p["lon"] for w in ways for p in w["geometry"]]
        if min(lats) <= lat <= max(lats) and min(lngs) <= lng <= max(lngs):
            return ways
    raise SystemExit(f"no OSM extract covers {lat},{lng}")


def hex_rgb(value):
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def fetch_map(entry, key=None):
    """Draws the map the app would show from OpenStreetMap streets, in the
    app's map colours, with the route on top."""
    _, _, w, h = entry["rect"]
    lat, lng, zoom = camera(entry)
    colors = style_colors(entry["style"])
    ss = SCALE * 2  # supersample, then shrink for anti-aliasing
    W, H = round(w * ss), round(h * ss)
    img = Image.new("RGB", (W, H), hex_rgb(colors.get("landscape", "#0a0a0a")))
    draw = ImageDraw.Draw(img)
    cx, cy = world(lat, lng)
    k = 2 ** zoom
    road_scale = 2 ** (zoom - 16)

    def px(la, ln):
        x, y = world(la, ln)
        return ((w / 2 + (x - cx) * k) * ss, (h / 2 + (y - cy) * k) * ss)

    def stroke(points, color, width):
        if len(points) < 2:
            return
        draw.line(points, fill=color, width=max(1, round(width)), joint="curve")
        r = width / 2
        for x, y in (points[0], points[-1]):
            draw.ellipse((x - r, y - r, x + r, y + r), fill=color)

    ways = osm_ways(lat, lng)
    order = sorted(ways, key=lambda wy: ROAD_WIDTH.get(wy.get("tags", {}).get("highway"), 0))
    for way in order:
        kind = way.get("tags", {}).get("highway")
        if kind not in ROAD_WIDTH:
            continue
        color = hex_rgb(colors["road.highway" if kind in HIGHWAY else "road"])
        stroke([px(p["lat"], p["lon"]) for p in way["geometry"]], color,
               ROAD_WIDTH[kind] * road_scale * ss)
    for line in entry["polylines"]:
        argb = line["color"]
        color = hex_rgb(argb[2:])
        stroke([px(a, b) for a, b in line["points"]], color, line["width"] * ss)
    img = img.resize((round(w * SCALE), round(h * SCALE)), Image.LANCZOS)
    return img, (lat, lng, zoom)


def hue_rgb(hue):
    import colorsys
    r, g, b = colorsys.hsv_to_rgb(hue / 360, 0.85, 0.95)
    return int(r * 255), int(g * 255), int(b * 255)


def draw_markers(img, entry, cam):
    """Google's default pin, tinted by hue, centred on the point (the app
    anchors its markers at 0.5, 0.5)."""
    _, _, w, h = entry["rect"]
    lat, lng, zoom = cam
    cx, cy = world(lat, lng)
    k = 2 ** zoom
    draw = ImageDraw.Draw(img)
    for marker in entry["markers"]:
        icon = marker["icon"]
        hue = icon[1] if len(icon) > 1 else 0
        mx, my = world(*marker["position"])
        px = (w / 2 + (mx - cx) * k) * SCALE
        py = (h / 2 + (my - cy) * k) * SCALE
        # 27x43 dp pin, anchored at its centre.
        pw, ph = 27 * SCALE * 0.62, 43 * SCALE * 0.62
        top = py - ph / 2
        r = pw / 2
        fill = hue_rgb(hue)
        edge = tuple(int(c * 0.55) for c in fill)
        head = (px - r, top, px + r, top + 2 * r)
        draw.polygon([(px - r * 0.86, top + r * 1.5), (px + r * 0.86, top + r * 1.5), (px, top + ph)],
                     fill=fill, outline=edge)
        draw.ellipse(head, fill=fill, outline=edge, width=max(1, SCALE // 2))
        dot = r * 0.36
        draw.ellipse((px - dot, top + r - dot, px + dot, top + r + dot), fill=edge)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=255)
    return mask


def composite(name, key):
    sidecar = OUT / f"{name}.maps.json"
    base = Image.open(OUT / f"{name}.png").convert("RGB")
    black = Image.open(OUT / f"{name}_k.png").convert("RGB")
    white = Image.open(OUT / f"{name}_w.png").convert("RGB")
    for entry in json.loads(sidecar.read_text()):
        x, y, w, h = entry["rect"]
        box = tuple(round(v * SCALE) for v in (x, y, x + w, y + h))
        map_img, cam = fetch_map(entry, key)
        draw_markers(map_img, entry, cam)
        map_img = map_img.resize((box[2] - box[0], box[3] - box[1]))
        k = black.crop(box)
        wt = white.crop(box)
        out = Image.new("RGB", k.size)
        kp, wp, mp, op = k.load(), wt.load(), map_img.load(), out.load()
        for j in range(k.size[1]):
            for i in range(k.size[0]):
                kb, wb = kp[i, j], wp[i, j]
                # Over black the overlay shows as a*fg; over white as
                # a*fg + (1-a)*255. The difference gives the coverage.
                a = 1 - sum(wb[c] - kb[c] for c in range(3)) / (3 * 255)
                a = min(max(a, 0.0), 1.0)
                m = mp[i, j]
                op[i, j] = tuple(min(255, round(kb[c] + (1 - a) * m[c])) for c in range(3))
        radius = round(entry["radius"] * SCALE)
        base.paste(out, box[:2], rounded_mask(out.size, radius))
    base.save(OUT / f"{name}.png")
    print(f"{name}: map laid in")


if __name__ == "__main__":
    for name in sys.argv[1:]:
        composite(name, None)
