# Brag Plan: FitSocial Pulse

## Angle
"Post the moment. Not the whole workout." Pulse as it really works: the rings at the top of Home, writing one in the composer (typed, Neon, then Strong), the viewer with its running progress bar, a run shared onto a Pulse, and your own Pulse's viewer list.

## Tone
chaotic, kept readable: punchier cuts and a faster track (vol-10, 110 BPM) at 0.36. Vertical, 30 s.

## Storyboard (beat grid)
1. 0-3.01 Hook over the Home Pulse rings, small zoom.
2. 3.01-8.73 "SAY IT IN A PULSE." / "Six typefaces. Twelve colours." composer clip.
3. 8.73-12.56 "UP FOR 24 HOURS." / "Then it is gone." viewer clip.
4. 12.56-18.01 "SHARE ANY POST TO IT." / "The author gets told." share screen, tap Share Pulse.
5. 18.01-22.92 "SEE WHO WATCHED." / "Your Pulse lists who viewed it." own Pulse + Viewers sheet.
6. 22.92- end card.

## Claims checked against code
Six fonts and twelve colours (pulse_text_style.dart), 24 h expiry (pulse_models.dart), author notified on share (commit 1b8f9e6), viewers list on your own Pulse only (pulse_viewer_screen.dart `entry.isOwn`).
