"""Builds run routes that follow real OpenStreetMap paths.

Shortest path over the extract's walkable ways, through hand-picked
waypoints, preferring promenades and footpaths the way a runner would.
Writes routes/<name>.json as [[lat, lng], ...].

    python tool/marketing_shots/osm_route.py
"""
import heapq
import json
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Cost multipliers: lower is preferred.
PREFER = {
    "footway": 0.6, "pedestrian": 0.6, "path": 0.7, "cycleway": 0.7,
    "living_street": 0.9, "residential": 1.0, "unclassified": 1.0,
    "service": 1.2, "tertiary": 1.1, "secondary": 1.2, "primary": 1.4,
    "track": 1.2, "steps": 2.0,
}

ROUTES = {
    # uShaka, north up the promenade past the piers to Battery Beach, back
    # down Snell Parade and OR Tambo Parade.
    "durban": ("durban", [
        (-29.8672, 31.0462), (-29.8560, 31.0418), (-29.8440, 31.0372),
        (-29.8320, 31.0335), (-29.8280, 31.0300), (-29.8400, 31.0330),
        (-29.8540, 31.0385), (-29.8672, 31.0462),
    ]),
    # Mouille Point lighthouse along Beach Road to Sea Point pavilion and back
    # through Main Road.
    "seapoint": ("seapoint", [
        (-33.8995, 18.4035), (-33.9060, 18.3960), (-33.9120, 18.3880),
        (-33.9165, 18.3830), (-33.9150, 18.3860), (-33.9085, 18.3950),
        (-33.9020, 18.4030), (-33.8995, 18.4035),
    ]),
}


def dist(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    dx = (b[1] - a[1]) * 111320 * math.cos(lat)
    dy = (b[0] - a[0]) * 110540
    return math.hypot(dx, dy)


def graph(extract):
    data = json.loads((HERE / "osm" / f"{extract}.json").read_text(encoding="utf-8"))
    edges = {}
    for way in data["elements"]:
        kind = way.get("tags", {}).get("highway")
        if kind not in PREFER or not way.get("geometry"):
            continue
        pts = [(round(p["lat"], 7), round(p["lon"], 7)) for p in way["geometry"]]
        for a, b in zip(pts, pts[1:]):
            cost = dist(a, b) * PREFER[kind]
            edges.setdefault(a, []).append((b, cost))
            edges.setdefault(b, []).append((a, cost))
    return edges


def nearest(edges, point):
    return min(edges, key=lambda n: dist(n, point))


def shortest(edges, start, goal):
    queue = [(0, start)]
    came = {start: None}
    best = {start: 0}
    while queue:
        cost, node = heapq.heappop(queue)
        if node == goal:
            break
        if cost > best[node]:
            continue
        for nxt, step in edges.get(node, []):
            total = cost + step
            if total < best.get(nxt, float("inf")):
                best[nxt] = total
                came[nxt] = node
                heapq.heappush(queue, (total, nxt))
    path, node = [], goal
    while node is not None:
        path.append(node)
        node = came.get(node)
    return path[::-1]


def main():
    out = HERE / "routes"
    out.mkdir(exist_ok=True)
    for name, (extract, waypoints) in ROUTES.items():
        edges = graph(extract)
        snapped = [nearest(edges, w) for w in waypoints]
        route = []
        for a, b in zip(snapped, snapped[1:]):
            leg = shortest(edges, a, b)
            route.extend(leg if not route else leg[1:])
        km = sum(dist(a, b) for a, b in zip(route, route[1:])) / 1000
        (out / f"{name}.json").write_text(json.dumps(route))
        print(f"{name}: {len(route)} points, {km:.2f} km")


if __name__ == "__main__":
    main()
