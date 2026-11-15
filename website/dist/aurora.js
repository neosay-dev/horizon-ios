/*! PixelAurora adapted from horizon-rust/horizon-site, MIT.
Copyright (c) 2026 Ludovic Marie and the Horizon contributors.
Source revision df8a595b9da4ff87716be7f3ea0fcba2ac198d16. */
(() => {
  const RAMP = ["#100a1f", "#151136", "#1d1444", "#281850", "#361b5b", "#481e66", "#5d236e", "#752873", "#902f76", "#ab3a75"];
  const BAYER = [
    0,
    32,
    8,
    40,
    2,
    34,
    10,
    42,
    48,
    16,
    56,
    24,
    50,
    18,
    58,
    26,
    12,
    44,
    4,
    36,
    14,
    46,
    6,
    38,
    60,
    28,
    52,
    20,
    62,
    30,
    54,
    22,
    3,
    35,
    11,
    43,
    1,
    33,
    9,
    41,
    51,
    19,
    59,
    27,
    49,
    17,
    57,
    25,
    15,
    47,
    7,
    39,
    13,
    45,
    5,
    37,
    63,
    31,
    55,
    23,
    61,
    29,
    53,
    21
  ].map((v) => (v + 0.5) / 64);
  function abgr(value) {
    const n = parseInt(value.slice(1), 16);
    return (4278190080 | (n & 255) << 16 | n & 65280 | n >> 16 & 255) >>> 0;
  }
  const COLORS = RAMP.map(abgr);
  const TOP = COLORS.length - 1;
  const MOON = [
    "aaaaaaaaaaab",
    "abbaaaaaaabb",
    "abccbaaaabcb",
    "abccbaaaaabb",
    "aabbaaaaaaab",
    "aaaaaabbaaab",
    "aaaaabccbaab",
    "abbaabccbaab",
    "bccbaabbaabb",
    "abbaaaaaabcb",
    "aaaaaaaaaabb",
    "abbbbbbbbbbb"
  ];
  const MOON_SIZE = MOON.length;
  const MOON_COLORS = { a: abgr("#fff3d6"), b: abgr("#e3d5b5"), c: abgr("#bfae90") };
  const STAR_BRIGHT = abgr("#e9e1ff");
  const STAR_DIM = abgr("#8f7fc4");
  const ease = (v) => v <= 0 ? 0 : v >= 1 ? 1 : v * v * (3 - 2 * v);
  const scatter = (i) => {
    const s = Math.sin(i * 127.1 + 311.7) * 43758.5453;
    return s - Math.floor(s);
  };
  function createField(ctx, width, height, moonTop) {
    const px = Math.min(6, Math.max(3, Math.round(window.innerWidth / 340)));
    const w = Math.ceil(width / px);
    const h = Math.ceil(height / px);
    const image = ctx.createImageData(w, h);
    const inset = width >= 1024 ? 40 : 24;
    const right = (width >= 1152 ? (width + 1152) / 2 : width) - inset;
    const moon = { x: Math.round(right / px) - MOON_SIZE, y: Math.round(moonTop / px) };
    const stars = [];
    for (let i = 0; stars.length < Math.round(w / 30) && i < 200; i++) {
      const x = Math.round(w * (0.5 + 0.5 * scatter(i)));
      const y = Math.round((Math.min(h * 0.3, 160 / px) + (moonTop - 32) / px) * scatter(i + 500));
      const nearMoon = x > moon.x - 3 && x < moon.x + MOON_SIZE + 3 && y > moon.y - 3 && y < moon.y + MOON_SIZE + 3;
      if (!nearMoon && x < w) stars.push({ x, y, phase: scatter(i + 900) * 6.3, speed: 0.6 + scatter(i + 1300) * 1.4 });
    }
    return {
      w,
      h,
      px,
      height,
      image,
      buf: new Uint32Array(image.data.buffer),
      front: new Float32Array(w),
      frontRays: new Float32Array(w),
      back: new Float32Array(w),
      backRays: new Float32Array(w),
      moon,
      stars
    };
  }
  function paint(f, t) {
    const { w, h, px, height, buf, front, frontRays, back, backRays } = f;
    for (let x = 0; x < w; x++) {
      const cx = (x + 0.5) * px;
      front[x] = height * (0.8 + 0.07 * Math.sin(cx * 4e-3 + t * 0.32) + 0.035 * Math.sin(cx * 0.011 - t * 0.55));
      frontRays[x] = 0.55 + 0.45 * Math.sin(cx * 0.03 + 2.6 * Math.sin(cx * 5e-3 + t * 0.38) + t * 0.25);
      back[x] = height * (0.6 + 0.06 * Math.sin(cx * 3e-3 - t * 0.21 + 2) + 0.03 * Math.sin(cx * 9e-3 + t * 0.4));
      backRays[x] = 0.5 + 0.5 * Math.sin(cx * 0.022 - 2 * Math.sin(cx * 4e-3 - t * 0.27) - t * 0.18);
    }
    const rise = height * 0.24;
    const edge = 2 * (height * 0.03) ** 2;
    const fadeTop = Math.min(140, height * 0.2);
    const fadeBottom = Math.min(100, height * 0.15);
    const { moon, stars } = f;
    const mx = moon.x + MOON_SIZE / 2;
    const my = moon.y + MOON_SIZE / 2;
    const haloR = MOON_SIZE * 2.4;
    const halo = 5 * (1 + 0.08 * Math.sin(t * 0.7));
    for (let y = 0; y < h; y++) {
      const cy = (y + 0.5) * px;
      const wash = 0.25 + 0.35 * (cy / height);
      const fade = ease(cy / fadeTop) * ease((height - cy) / fadeBottom);
      const dy = Math.abs(y + 0.5 - my);
      const haloRow = dy < haloR ? halo * ease(cy / 40) : 0;
      const row = (y & 7) * 8;
      for (let x = 0; x < w; x++) {
        const df = front[x] - cy;
        const db = back[x] - cy;
        const lit = (df > 0 ? Math.exp(-df / rise) * frontRays[x] : Math.exp(-(df * df) / edge)) * 7.5 + (db > 0 ? Math.exp(-db / rise) * backRays[x] : Math.exp(-(db * db) / edge)) * 2.5;
        let level = (wash + lit) * fade;
        if (haloRow) {
          const d = Math.max(dy, Math.abs(x + 0.5 - mx));
          if (d < haloR) level += haloRow * (1 - d / haloR) ** 2;
        }
        const base = Math.floor(level);
        const step = level - base > BAYER[row + (x & 7)] ? base + 1 : base;
        buf[y * w + x] = COLORS[step > TOP ? TOP : step];
      }
    }
    for (const s of stars) {
      const twinkle = 0.5 + 0.5 * Math.sin(t * s.speed + s.phase);
      if (twinkle < 0.35 || s.y < 1 || s.y >= h - 1 || s.x < 1 || s.x >= w - 1) continue;
      const i = s.y * w + s.x;
      buf[i] = twinkle > 0.8 ? STAR_BRIGHT : STAR_DIM;
      if (twinkle > 0.93) buf[i - 1] = buf[i + 1] = buf[i - w] = buf[i + w] = STAR_DIM;
    }
    for (let r = 0; r < MOON_SIZE; r++) {
      const y = moon.y + r;
      if (y < 0 || y >= h) continue;
      for (let c = 0; c < MOON_SIZE; c++) {
        const x = moon.x + c;
        if (x >= 0 && x < w) buf[y * w + x] = MOON_COLORS[MOON[r][c]];
      }
    }
  }
  function mountAurora() {
    const moonTop = 32;
    const canvas = document.getElementById("community-aurora");
    const parent = canvas?.parentElement;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !parent || !ctx) return;
    const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
    let still = preference.matches;
    let field = null;
    let time = 20;
    let last = 0;
    let raf = 0;
    let visible = false;
    const draw = () => {
      if (!field) return;
      paint(field, time);
      ctx.putImageData(field.image, 0, 0);
      canvas.dataset.ready = "";
    };
    const resize = () => {
      const { clientWidth, clientHeight } = parent;
      if (!clientWidth || !clientHeight) return;
      field = createField(ctx, clientWidth, clientHeight, moonTop);
      canvas.width = field.w;
      canvas.height = field.h;
      canvas.style.width = `${field.w * field.px}px`;
      canvas.style.height = `${field.h * field.px}px`;
      draw();
    };
    const tick = (now) => {
      raf = requestAnimationFrame(tick);
      if (now - last < 31) return;
      time += last ? Math.min(now - last, 100) / 1e3 : 0;
      last = now;
      draw();
    };
    const start = () => {
      if (!raf && !still && visible && !document.hidden) raf = requestAnimationFrame(tick);
    };
    const stop = () => {
      cancelAnimationFrame(raf);
      raf = 0;
      last = 0;
    };
    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(parent);
    const visibilityObserver = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) start();
      else stop();
    });
    visibilityObserver.observe(parent);
    const onPreference = () => {
      still = preference.matches;
      if (still) {
        stop();
        draw();
      } else start();
    };
    const onVisibility = () => document.hidden ? stop() : start();
    preference.addEventListener("change", onPreference);
    document.addEventListener("visibilitychange", onVisibility);
    resize();
    return () => {
      stop();
      preference.removeEventListener("change", onPreference);
      document.removeEventListener("visibilitychange", onVisibility);
      resizeObserver.disconnect();
      visibilityObserver.disconnect();
    };
  }
  mountAurora();
})();
