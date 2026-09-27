/*
 * FitSocial brag kit: builds the phone, screens and headline type for a
 * vertical 1080x1920 composition and adds their motion to one GSAP timeline.
 *
 * Screens are the app's own renders (1179x2556, 393x852 logical). Everything
 * here is positioned in logical phone pixels and scaled by U.
 *
 *   const kit = FitKit.create(root, { phoneWidth: 640, phoneTop: 470 });
 *   kit.pane('feed', { scroll: { long, top, fixedTop, fixedBottom, under } });
 *   kit.show('feed', 3.0);             // push in at t = 3.0
 *   kit.scroll('feed', 3.4, 7.6, 900); // scroll to 900 logical px
 *   kit.headline(3.0, 8.0, 'RUNS. LIFTS. MEALS.', 'From the people ...');
 *
 * Deterministic: no clocks, no randomness, every tween at an absolute time.
 */
(function () {
  const LW = 393; // logical phone width
  const LH = 852; // logical phone height

  function el(tag, cls, parent, style) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (style) Object.assign(node.style, style);
    if (parent) parent.appendChild(node);
    return node;
  }

  function create(root, opts) {
    const o = Object.assign({ phoneWidth: 640, phoneTop: 470, bezel: 10, statusTime: '05:42' }, opts || {});
    const U = o.phoneWidth / LW;
    const tl = gsap.timeline({ paused: true });
    const W = 1080;

    // Ground: the app's black with an ember glow the music breathes.
    const ground = el('div', 'fk-ground', root);
    const glow = el('div', 'fk-glow', root, {
      left: (W - 1100) / 2 + 'px', top: o.phoneTop - 120 + 'px', width: '1100px', height: '1300px',
    });

    // Headline layer.
    const type = el('div', 'fk-type', root);

    // Phone.
    const phone = el('div', 'fk-phone', root, {
      left: (W - o.phoneWidth) / 2 - o.bezel + 'px',
      top: o.phoneTop - o.bezel + 'px',
      width: o.phoneWidth + 2 * o.bezel + 'px',
      height: LH * U + 2 * o.bezel + 'px',
      padding: o.bezel + 'px',
      borderRadius: 56 + o.bezel + 'px',
    });
    // The phone rises from and falls below the frame.
    phone.setAttribute('data-layout-allow-overflow', '');
    const screen = el('div', 'fk-screen', phone, {
      width: o.phoneWidth + 'px', height: LH * U + 'px', borderRadius: '56px',
    });
    // Panes live on a stage inside the screen, so a punch-in scales the app
    // and not the status bar or the phone's clip.
    const stage = el('div', 'fk-stage', screen);
    const status = el('div', 'fk-status', screen, { height: 40 * U + 'px', fontSize: 14.5 * U + 'px', padding: '0 ' + 26 * U + 'px' });
    status.innerHTML =
      '<span>' + o.statusTime + '</span><span class="fk-icons">' +
      '<svg viewBox="0 0 18 12" width="' + 17 * U + '"><path fill="#F7F7F7" d="M1 11h2V8H1zm4 0h2V6H5zm4 0h2V3H9zm4 0h2V0h-2z"/></svg>' +
      '<svg viewBox="0 0 16 12" width="' + 15 * U + '"><path fill="#F7F7F7" d="M8 11.5 5.6 8.9a3.4 3.4 0 0 1 4.8 0zM3.5 6.8a6.4 6.4 0 0 1 9 0l-1.4 1.4a4.4 4.4 0 0 0-6.2 0zM1.3 4.6a9.5 9.5 0 0 1 13.4 0l-1.4 1.4a7.5 7.5 0 0 0-10.6 0z"/></svg>' +
      '<svg viewBox="0 0 26 12" width="' + 24 * U + '"><rect x="0.5" y="0.5" width="22" height="11" rx="3" fill="none" stroke="#F7F7F7" stroke-opacity=".5"/><rect x="2" y="2" width="15" height="8" rx="1.6" fill="#F7F7F7"/><rect x="23.5" y="4" width="1.8" height="4" rx=".9" fill="#F7F7F7" fill-opacity=".5"/></svg>' +
      '</span>';

    const panes = {};
    let current = null;

    function slice(parent, src, fromTop, height, atBottom) {
      // A strip of a normal-height capture pinned over a scrolling one: the
      // glass bar, the app bar or the floating nav that does not scroll.
      const s = el('div', 'fk-slice', parent, {
        height: height * U + 'px',
        backgroundImage: 'url(' + src + ')',
        // Width pinned, height from the image: the strip may come from a
        // tall capture.
        backgroundSize: LW * U + 'px auto',
        backgroundPosition: atBottom ? '0 100%' : '0 0',
      });
      s.style[atBottom ? 'bottom' : 'top'] = '0';
      return s;
    }

    function pane(name, spec) {
      const p = el('div', 'fk-pane', stage);
      p.style.zIndex = 1;
      // Panes wait off to the right until they are pushed in.
      p.setAttribute('data-layout-allow-overflow', '');
      const entry = { node: p, spec: spec, y: 0 };
      if (spec.still) {
        el('img', 'fk-img', p).src = spec.still;
      } else if (spec.video) {
        // A clip captured from the app: its first frame holds until it plays,
        // its last frame holds after.
        const v = spec.video;
        el('img', 'fk-img', p).src = v.first;
        const last = el('img', 'fk-img', p);
        last.src = v.last;
        gsap.set(last, { opacity: 0 });
        // The renderer only extracts frames for <video> tags present in the
        // page's static HTML (tools/static_videos.py writes them), so adopt
        // that tag rather than creating one.
        let vid = document.getElementById('clip-' + name);
        if (vid) {
          p.appendChild(vid);
          vid.className = 'fk-img';
        } else {
          vid = el('video', 'fk-img', p);
          vid.id = 'clip-' + name;
          vid.src = v.src;
          vid.muted = true;
          vid.setAttribute('muted', '');
          vid.setAttribute('playsinline', '');
          vid.setAttribute('data-start', String(v.start));
          vid.setAttribute('data-duration', String(v.dur));
        }
        tl.set(last, { opacity: 1 }, v.start + v.dur - 0.04);
      } else if (spec.frames) {
        entry.frames = spec.frames.map(function (src, i) {
          const img = el('img', 'fk-img', p);
          img.src = src;
          img.style.opacity = i === 0 ? 1 : 0;
          return img;
        });
      } else if (spec.scroll) {
        const sc = spec.scroll;
        const top = sc.under ? 0 : sc.fixedTop;
        const view = el('div', 'fk-view', p, { top: top * U + 'px', bottom: (sc.fixedBottom || 0) * U + 'px' });
        const long = el('img', 'fk-long', view, { top: -top * U + 'px', width: LW * U + 'px' });
        long.src = sc.long;
        entry.long = long;
        if (sc.fixedTop) slice(p, sc.top, 0, sc.fixedTop, false);
        if (sc.fixedBottom) slice(p, sc.top, 0, sc.fixedBottom, true);
      }
      gsap.set(p, { xPercent: 100, opacity: 1 });
      panes[name] = entry;
      return entry;
    }

    // Brings a pane on screen. The first is simply there; later ones push in
    // from the right the way a route opens, the old one easing left under it.
    function show(name, t, mode) {
      const next = panes[name];
      const prev = current;
      mode = mode || (prev ? 'push' : 'cut');
      next.node.style.zIndex = 2;
      if (mode === 'cut') {
        tl.set(next.node, { xPercent: 0, zIndex: 2 }, t);
      } else if (mode === 'fade') {
        tl.set(next.node, { xPercent: 0, opacity: 0, zIndex: 3 }, t);
        tl.to(next.node, { opacity: 1, duration: 0.35, ease: 'power1.out' }, t);
      } else {
        tl.set(next.node, { zIndex: 3 }, t);
        tl.fromTo(next.node, { xPercent: 100 }, { immediateRender: false, xPercent: 0, duration: 0.55, ease: 'power3.out' }, t);
        if (prev) {
          tl.fromTo(prev.node, { xPercent: 0, filter: 'brightness(1)' },
            { immediateRender: false, xPercent: -28, filter: 'brightness(0.45)', duration: 0.55, ease: 'power3.out' }, t);
        }
      }
      if (prev) tl.set(prev.node, { zIndex: 1 }, t + 0.6);
      current = next;
    }

    function scroll(name, t0, t1, toY, fromY) {
      const p = panes[name];
      const from = fromY == null ? p.y : fromY;
      tl.fromTo(p.long, { y: -from * U }, { immediateRender: false, y: -toY * U, duration: t1 - t0, ease: 'power2.inOut' }, t0);
      p.y = toY;
    }

    function flip(name, times) {
      const p = panes[name];
      times.forEach(function (t, i) {
        if (i === 0) return;
        tl.set(p.frames[i], { opacity: 1 }, t);
        tl.set(p.frames[i - 1], { opacity: 0 }, t + 0.001);
      });
    }

    // Slow push-in on a point of the screen (logical coordinates).
    function punch(t0, t1, scale, lx, ly) {
      tl.fromTo(stage, { scale: 1, transformOrigin: lx * U + 'px ' + ly * U + 'px' },
        { immediateRender: false, scale: scale, duration: t1 - t0, ease: 'power1.inOut' }, t0);
      tl.to(stage, { scale: 1, duration: 0.35, ease: 'power2.inOut' }, t1);
    }

    // A finger on glass: dot lands, holds, lifts.
    function touch(t0, t1, lx, ly) {
      const d = el('div', 'fk-touch', screen, { left: lx * U - 28 + 'px', top: ly * U - 28 + 'px' });
      gsap.set(d, { opacity: 0 });
      tl.fromTo(d, { scale: 1.6, opacity: 0 }, { immediateRender: false, scale: 1, opacity: 1, duration: 0.18, ease: 'power2.out' }, t0);
      tl.to(d, { scale: 1.25, opacity: 0, duration: 0.25, ease: 'power1.in' }, t1);
    }

    // A finger that moves: [[t, lx, ly], ...], landing at the first point and
    // lifting at t1.
    function drag(path, t1) {
      const [t0, x0, y0] = path[0];
      const d = el('div', 'fk-touch', screen, { left: '-28px', top: '-28px' });
      gsap.set(d, { opacity: 0, x: x0 * U, y: y0 * U });
      tl.fromTo(d, { scale: 1.6, opacity: 0 }, { immediateRender: false, scale: 1, opacity: 1, duration: 0.18, ease: 'power2.out' }, t0);
      for (let i = 1; i < path.length; i++) {
        const [t, x, y] = path[i];
        const prev = path[i - 1][0];
        tl.to(d, { x: x * U, y: y * U, duration: Math.max(0.01, t - prev), ease: 'sine.inOut' }, prev);
      }
      tl.to(d, { scale: 1.25, opacity: 0, duration: 0.25, ease: 'power1.in' }, t1);
    }

    function headline(t0, t1, text, sub, opts2) {
      const h = el('div', 'fk-headline', type);
      const o2 = opts2 || {};
      const lines = Array.isArray(text) ? text : [text];
      lines.forEach(function (line) {
        const l = el('div', 'fk-line', h);
        l.innerHTML = line;
        // Anton's font box is far taller than its caps; stacked lines overlap
        // as boxes while the glyphs keep clear.
        if (lines.length > 1) l.setAttribute('data-layout-allow-overlap', '');
        if (o2.size) l.style.fontSize = o2.size + 'px';
      });
      if (sub) el('div', 'fk-sub', h).textContent = sub;
      const parts = h.children;
      gsap.set(h, { opacity: 0 });
      gsap.set(parts, { opacity: 0 });
      tl.set(h, { opacity: 1 }, t0);
      for (let i = 0; i < parts.length; i++) {
        const at = t0 + (o2.stagger ? o2.stagger[i] || 0 : i * 0.08);
        tl.fromTo(parts[i], { y: 34, opacity: 0 }, { immediateRender: false, y: 0, opacity: 1, duration: 0.45, ease: 'power3.out' }, at);
      }
      if (t1 != null) tl.to(h, { opacity: 0, y: -16, duration: 0.28, ease: 'power2.in' }, t1 - 0.28);
      return h;
    }

    gsap.set(glow, { opacity: 0 });

    function phoneIn(t, from) {
      gsap.set(phone, { y: from == null ? 1500 : from });
      tl.fromTo(phone, { y: from == null ? 1500 : from }, { immediateRender: false, y: 0, duration: 0.9, ease: 'power3.out' }, t);
      tl.fromTo(glow, { opacity: 0 }, { immediateRender: false, opacity: 1, duration: 0.9, ease: 'power1.out' }, t);
    }

    function phoneOut(t) {
      tl.to(phone, { y: 1500, duration: 0.7, ease: 'power3.in' }, t);
      tl.to(type, { opacity: 0, duration: 0.3 }, t);
    }

    // The FitSocialLogo wordmark as the widget builds it: the F mark, tucked
    // 10% under "itSocial" in heavy italic, "it" in brand orange.
    function wordmark(t, size, markSrc, tagline) {
      const wrap = el('div', 'fk-end', root);
      const row = el('div', 'fk-mark-row', wrap);
      const markH = size * 0.95;
      const mark = el('img', 'fk-mark', row, { height: markH + 'px', marginRight: -size * 0.10 + 'px' });
      mark.src = markSrc;
      const word = el('div', 'fk-word', row, { fontSize: size + 'px' });
      word.innerHTML = '<span class="fk-it">it</span>Social';
      const tag = el('div', 'fk-tagline', wrap);
      tag.textContent = tagline;
      gsap.set([row, tag], { opacity: 0 });
      tl.fromTo(row, { scale: 0.86, opacity: 0 }, { immediateRender: false, scale: 1, opacity: 1, duration: 0.6, ease: 'back.out(1.6)' }, t);
      tl.fromTo(tag, { y: 26, opacity: 0 }, { immediateRender: false, y: 0, opacity: 1, duration: 0.5, ease: 'power3.out' }, t + 0.55);
      return wrap;
    }

    // Bass swells the ember glow; nothing else listens to the music.
    function breathe(data, t0, t1) {
      if (!data) return;
      const first = Math.floor(t0 * data.fps);
      const last = Math.min(data.totalFrames, Math.ceil(t1 * data.fps));
      for (let f = first; f < last; f++) {
        const b = data.frames[f].bass;
        tl.set(glow, { scale: 1 + 0.07 * b, filter: 'brightness(' + (0.8 + 0.45 * b).toFixed(3) + ')' }, f / data.fps);
      }
    }

    return {
      tl, U, phone, screen, stage, glow, root,
      pane, show, scroll, flip, punch, touch, drag, headline, phoneIn, phoneOut, wordmark, breathe,
    };
  }

  window.FitKit = { create };
})();
