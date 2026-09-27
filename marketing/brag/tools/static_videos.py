"""Writes the <video> tags a composition's clips need into its static HTML.

Hyperframes pre-extracts frames only for <video> elements it finds in the
page source; a video created by script renders as its first frame. This reads
every kit.pane('name', clip('file', start, dur)) call in index.html and puts a
matching <video id="clip-name"> inside #root (replacing any written before).

    python tools/static_videos.py <slug> [<slug> ...]
"""
import re
import sys
from pathlib import Path

OUT = Path(__file__).resolve().parents[1] / "output"
CALL = re.compile(r"kit\.pane\('([\w-]+)',\s*clip\('([\w-]+)',\s*([\d.]+),\s*([\d.]+)\)\)")
BLOCK = re.compile(r"\n\s*<!-- clips -->.*?<!-- /clips -->", re.S)

for slug in sys.argv[1:]:
    path = OUT / slug / "composition" / "index.html"
    html = BLOCK.sub("", path.read_text(encoding="utf-8"))
    tags = [
        f'      <video id="clip-{name}" src="assets/clips/{src}.mp4" data-start="{start}" '
        f'data-duration="{dur}" muted playsinline></video>'
        for name, src, start, dur in CALL.findall(html)
    ]
    block = "\n      <!-- clips -->\n" + "\n".join(tags) + "\n      <!-- /clips -->"
    html = re.sub(r'(<div id="root"[^>]*>)', lambda m: m.group(1) + block, html, count=1)
    path.write_text(html, encoding="utf-8")
    print(f"{slug}: {len(tags)} clip tag(s)")
