// Adapted from horizon-rust/horizon-site/components/horizon-scene.tsx.
// Upstream df8a595b9da4ff87716be7f3ea0fcba2ac198d16 (MIT).
// Copyright (c) 2026 Ludovic Marie and the Horizon contributors.
// React lifecycle replaced with DOM setup; motion also pauses in hidden tabs.
(() => {
function hex(value: string) {
  const n = parseInt(value.slice(1), 16);
  return (0xff000000 | ((n & 0xff) << 16) | (n & 0xff00) | ((n >> 16) & 0xff)) >>> 0;
}

function mix(a: number, b: number, t: number) {
  const ar = a & 0xff;
  const ag = (a >>> 8) & 0xff;
  const ab = (a >>> 16) & 0xff;
  const r = ar + ((b & 0xff) - ar) * t;
  const g = ag + (((b >>> 8) & 0xff) - ag) * t;
  const bl = ab + (((b >>> 16) & 0xff) - ab) * t;
  return (0xff000000 | (bl << 16) | (g << 8) | r) >>> 0;
}

const rgba = (c: number, a: number) => `rgba(${c & 0xff},${(c >>> 8) & 0xff},${(c >>> 16) & 0xff},${a})`;

const SKY = [
  "#0a0919", "#0f0c28", "#151136", "#1d1444", "#281850", "#361b5b",
  "#481e66", "#5d236e", "#752873", "#902f76", "#ab3a75", "#c64a71",
  "#de5f6a", "#ef7c63", "#f89d62",
].map(hex);
const SKY_STEPS = SKY.length - 4;
const SUN = ["#fff5d2", "#ffe4a0", "#ffca78", "#ffac5f", "#ff8c58", "#fb6c62", "#ee5277"].map(hex);
const HALO = hex("#ff8d6a");
const FOG = hex("#e0697c");
const RIM = hex("#ffb27c");
const CLOUD_HIGH = hex("#5f2c7c");
const CLOUD_LOW = hex("#c95985");
const CLOUD_TOP = hex("#f3a6bd");
const FIREFLY = hex("#ffd98c");

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const smoothstep = (a: number, b: number, v: number) => {
  const t = clamp((v - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};

function rng(seed: number) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function noise1d(seed: number) {
  const lattice = Float32Array.from({ length: 256 }, rng(seed));
  return (x: number) => {
    let value = 0;
    let amp = 0.5;
    let freq = 1;
    let norm = 0;
    for (let o = 0; o < 4; o++) {
      const p = x * freq;
      const i = Math.floor(p);
      const s = p - i;
      const a = lattice[i & 255];
      const b = lattice[(i + 1) & 255];
      value += (a + (b - a) * s * s * (3 - 2 * s)) * amp;
      norm += amp;
      amp *= 0.5;
      freq *= 2.1;
    }
    return value / norm;
  };
}

const TREES = [
  ["..###..", ".#####.", "#######", "#######", ".#####.", "...#...", "...#..."],
  ["..#..", "..#..", ".###.", "..#..", ".###.", "#####", "..#..", "..#.."],
  [".###.", "#####", "#####", "..#..", "..#.."],
].map((rows) => ({ rows, w: rows[0].length, h: rows.length, trunk: rows[rows.length - 1].indexOf("#") }));

type Tree = { col: number; sprite: (typeof TREES)[number] };

type Ridge = {
  top: Int16Array;
  depth: number;
  color: number;
  rim: number;
  rimStrength: number;
  trees: Tree[];
};

type Cloud = {
  x0: number;
  y: number;
  w: number;
  h: number;
  mask: Uint8Array;
  speed: number;
  depth: number;
  body: number;
  rimBase: number;
};

type Star = { x: number; y: number; size: number; b: number; phase: number; speed: number; sparkle: boolean; cool: boolean };
type Firefly = { x: number; y: number; phase: number; blink: number };

type Scene = {
  width: number;
  height: number;
  px: number;
  w: number;
  h: number;
  horizon: number;
  fogTop: number;
  fogBottom: number;
  sun: { x: number; y: number; r: number };
  sky: HTMLCanvasElement;
  glow: Float32Array;
  stars: Star[];
  clouds: Cloud[];
  ridges: Ridge[];
  flies: Firefly[];
  showSun: boolean;
};

type View = { x: number; y: number; sink: number };

const MARGIN = 20;

function makeCloud(rand: () => number, w: number, h: number) {
  const mask = new Uint8Array(w * h);
  const lobe = (from: number, to: number) => {
    let left = from;
    let right = to;
    let y = h;
    while (y > 0 && right - left > 3) {
      for (let k = Math.min(y, 1 + Math.floor(rand() * 2)); k > 0; k--) {
        y--;
        for (let x = left; x < right; x++) mask[y * w + x] = 1;
      }
      const span = right - left;
      left += Math.max(1, Math.round(span * (0.06 + rand() * 0.2)));
      right -= Math.max(1, Math.round(span * (0.06 + rand() * 0.2)));
    }
  };
  lobe(0, w);
  if (w > 24 && rand() < 0.75) {
    const a = Math.round(w * (0.1 + rand() * 0.4));
    lobe(a, Math.min(w, a + Math.round(w * (0.35 + rand() * 0.2))));
  }
  for (let i = 0; i < w * h; i++) {
    if (!mask[i]) continue;
    if (i >= (h - 1) * w) mask[i] = 2;
    else if (i < w || !mask[i - w]) mask[i] = 3;
  }
  return mask;
}

function paintStaticSky(width: number, height: number, dpr: number, horizon: number, sunX: number, fogTop: number) {
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(width * dpr);
  canvas.height = Math.round(height * dpr);
  const g = canvas.getContext("2d");
  if (!g) return canvas;
  g.scale(dpr, dpr);

  const base = g.createLinearGradient(0, 0, 0, horizon);
  for (let i = 0; i <= SKY_STEPS; i++) base.addColorStop(Math.pow(i / SKY_STEPS, 1 / 2.3), rgba(SKY[i], 1));
  g.fillStyle = base;
  g.fillRect(0, 0, width, height);

  const ry = horizon * 0.32;
  g.save();
  g.translate(sunX, horizon);
  g.scale((width * 0.6) / ry, 1);
  const glow = g.createRadialGradient(0, 0, 0, 0, 0, ry);
  glow.addColorStop(0, rgba(SKY[14], 0.9));
  glow.addColorStop(0.3, rgba(SKY[13], 0.55));
  glow.addColorStop(0.65, rgba(SKY[12], 0.18));
  glow.addColorStop(1, rgba(SKY[12], 0));
  g.fillStyle = glow;
  g.fillRect(-ry, -ry, ry * 2, ry * 2);
  g.restore();

  const haze = g.createLinearGradient(0, fogTop, 0, horizon);
  haze.addColorStop(0, rgba(FOG, 0));
  haze.addColorStop(1, rgba(FOG, 0.3));
  g.fillStyle = haze;
  g.fillRect(0, fogTop, width, height - fogTop);
  return canvas;
}

function buildScene(
  width: number,
  height: number,
  landHeight: number,
  sunX: number,
  sunScale: number,
  sunRise: number,
  showSun: boolean,
  dpr: number,
): Scene {
  const px = clamp(Math.round(width / 340), 3, 6);
  const w = Math.ceil(width / px);
  const h = Math.ceil(height / px);
  const land = landHeight / px;
  const horizon = Math.round(h - land * 0.55);
  const r = Math.round(land * 0.4 * sunScale);
  const sun = { x: Math.round(w * sunX), y: Math.round(horizon - r * (0.45 + sunRise)), r };
  const fogTop = Math.round(horizon - land * 0.18);

  const glow = new Float32Array(w);
  for (let x = 0; x < w; x++) {
    const d = (x - sun.x) / (w * 0.3);
    glow[x] = Math.exp(-d * d);
  }

  const skyAt = (y: number) => {
    const f = Math.pow(clamp(y / horizon, 0, 1), 2.3) * SKY_STEPS;
    const i = Math.floor(f);
    return mix(SKY[i], SKY[Math.min(SKY.length - 1, i + 1)], f - i);
  };

  const rand = rng(7);
  const stars: Star[] = [];
  const skyHeight = horizon * px;
  const starCount = Math.round((width * skyHeight) / 5200);
  for (let i = 0; i < starCount; i++) {
    stars.push({
      x: rand() * width,
      y: 2 + Math.pow(rand(), 1.8) * skyHeight * 0.75,
      size: rand() < 0.15 ? 1.8 : 1 + rand() * 0.4,
      b: rand() < 0.1 ? 0.8 + rand() * 0.2 : 0.25 + rand() * 0.4,
      phase: rand() * Math.PI * 2,
      speed: 0.5 + rand() * 2,
      sparkle: rand() < 0.06,
      cool: rand() < 0.35,
    });
  }

  const clouds: Cloud[] = [];
  const addCloud = (y: number, cw: number, ch: number, speed: number, depth: number) => {
    const t = clamp((y - horizon * 0.45) / (horizon * 0.55), 0, 1);
    clouds.push({
      x0: rand() * (w + cw),
      y: Math.round(y),
      w: Math.round(cw),
      h: Math.round(ch),
      mask: makeCloud(rand, Math.round(cw), Math.round(ch)),
      speed,
      depth,
      body: mix(skyAt(y), mix(CLOUD_HIGH, CLOUD_LOW, t * t), 0.55),
      rimBase: 0.15 + t * 0.35,
    });
  };
  for (let i = 0; i < 3; i++) {
    const cw = (120 + rand() * 140) / px;
    addCloud(horizon - land * (0.45 + rand() * 0.25), cw, cw * (0.2 + rand() * 0.06), 0.5 + rand() * 0.8, 0.4);
  }
  for (let i = 0; i < 5; i++) {
    addCloud(horizon - 5 - rand() * land * 0.4, w * (0.08 + rand() * 0.12), 3 + rand() * 3, 1 + rand() * 1.6, 0.8);
  }

  const cols = w + MARGIN * 2;
  const ridge = (
    seed: number,
    base: number,
    amp: number,
    block: number,
    feature: number,
    valley: number,
    depth: number,
    color: string,
    rim: string,
    rimStrength: number,
  ): Ridge => {
    const n = noise1d(seed);
    const top = new Int16Array(cols);
    for (let i = 0; i < cols; i += block) {
      const x = i - MARGIN + block / 2;
      const d = Math.abs(x - sun.x) / (w * 0.5);
      const env = valley + (1 - valley) * Math.min(1, d * d * 1.8);
      const v = clamp((n((x * px) / feature) - 0.2) / 0.6, 0, 1);
      const y = Math.round((base - amp * env * v) / block) * block;
      for (let k = 0; k < block && i + k < cols; k++) top[i + k] = y;
    }
    return { top, depth, color: hex(color), rim: hex(rim), rimStrength, trees: [] };
  };

  const ridges = [
    ridge(11, horizon, land * 0.3, 2, 170, 0.2, 0.25, "#3f1f5c", "#c45a7f", 1),
    ridge(23, horizon + land * 0.22, land * 0.36, 3, 130, 0.35, 0.55, "#25123e", "#7a3068", 0.8),
    ridge(37, horizon + land * 0.5, land * 0.38, 4, 100, 0.5, 1, "#100a1f", "#2c1640", 0.6),
  ];

  const near = ridges[2];
  for (let col = MARGIN + Math.floor(rand() * 12); col < cols - 8; col += 14 + Math.floor(rand() * 30)) {
    near.trees.push({ col, sprite: TREES[Math.floor(rand() * TREES.length)] });
  }

  const flies: Firefly[] = [];
  for (let i = 0; i < Math.round(w / 36); i++) {
    flies.push({
      x: rand() * w,
      y: horizon + land * (0.3 + rand() * 0.6),
      phase: rand() * Math.PI * 2,
      blink: 0.6 + rand() * 0.9,
    });
  }

  return {
    width,
    height,
    px,
    w,
    h,
    horizon,
    fogTop,
    fogBottom: Math.round(horizon + land * 0.26),
    sun,
    sky: paintStaticSky(width, height, dpr, horizon * px, sun.x * px, fogTop * px),
    glow,
    stars,
    clouds,
    ridges,
    flies,
    showSun,
  };
}

const sunOffset = (view: View) => Math.round(-view.x * 1.5);

function renderSky(ctx: CanvasRenderingContext2D, s: Scene, time: number, view: View) {
  const { px } = s;
  const skyHeight = s.horizon * px;
  ctx.drawImage(s.sky, 0, 0, s.width, s.height);

  if (s.showSun) {
    const sx = (s.sun.x + sunOffset(view)) * px;
    const sy = (s.sun.y + view.sink) * px;
    const haloR = s.sun.r * 2.4 * px;
    const a = 0.5 * (0.9 + 0.1 * Math.sin(time * 0.9));
    const halo = ctx.createRadialGradient(sx, sy, 0, sx, sy, haloR);
    halo.addColorStop(0, rgba(HALO, a));
    halo.addColorStop(0.45, rgba(HALO, a * 0.3));
    halo.addColorStop(1, rgba(HALO, 0));
    ctx.fillStyle = halo;
    ctx.fillRect(sx - haloR, sy - haloR, haloR * 2, haloR * 2);
  }

  const shift = -view.x * 4;
  for (const star of s.stars) {
    const twinkle = 0.5 + 0.5 * Math.sin(time * star.speed + star.phase);
    const alpha = star.b * (1 - smoothstep(0.4, 0.82, star.y / skyHeight)) * (0.35 + 0.65 * twinkle);
    if (alpha < 0.04) continue;
    const x = star.x + shift;
    ctx.globalAlpha = alpha;
    ctx.fillStyle = star.cool ? "#d2c8ff" : "#fff3e4";
    ctx.beginPath();
    ctx.arc(x, star.y, star.size / 2, 0, Math.PI * 2);
    ctx.fill();
    if (star.sparkle && twinkle > 0.65) {
      const arm = (twinkle - 0.65) * 10;
      ctx.globalAlpha = alpha * 0.45;
      ctx.fillRect(x - arm, star.y - 0.3, arm * 2, 0.6);
      ctx.fillRect(x - 0.3, star.y - arm, 0.6, arm * 2);
    }
  }
  ctx.globalAlpha = 1;

  const window9 = Math.floor(time / 9);
  const meteor = rng(window9 * 7919 + 13);
  const age = time - window9 * 9 - (1 + meteor() * 5);
  if (age > 0 && age < 0.9 && meteor() < 0.8) {
    const dir = meteor() < 0.5 ? -1 : 1;
    const travel = s.width * 0.5 * age;
    const hx = s.width * (0.15 + meteor() * 0.7) + dir * 0.87 * travel;
    const hy = skyHeight * (0.05 + meteor() * 0.22) + 0.5 * travel;
    const tx = hx - dir * 0.87 * 110;
    const ty = hy - 0.5 * 110;
    const life = Math.sin((age / 0.9) * Math.PI);
    if (hy < skyHeight * 0.7) {
      const trail = ctx.createLinearGradient(hx, hy, tx, ty);
      trail.addColorStop(0, `rgba(255,243,228,${life})`);
      trail.addColorStop(1, "rgba(255,243,228,0)");
      ctx.strokeStyle = trail;
      ctx.lineWidth = 1.5;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(hx, hy);
      ctx.lineTo(tx, ty);
      ctx.stroke();
    }
  }
}

function drawSun(s: Scene, buf: Uint32Array, time: number, view: View) {
  const { w, h } = s;
  const sx = s.sun.x + sunOffset(view);
  const sy = s.sun.y + view.sink;
  const r = s.sun.r;
  const stripeStart = 0.38;
  const stripe = Math.max(4, Math.round(r / 5));
  const phase = time * 2.2;
  for (let y = Math.max(0, Math.ceil(sy - r)); y <= Math.min(h - 1, Math.floor(sy + r)); y++) {
    const dy = y + 0.5 - sy;
    const half = Math.sqrt(r * r - dy * dy);
    if (!(half > 0)) continue;
    const v = (dy + r) / (2 * r);
    if (v > stripeStart) {
      const gap = 1 + ((v - stripeStart) / (1 - stripeStart)) * stripe * 0.6;
      if ((((y - sy - phase) % stripe) + stripe) % stripe < gap) continue;
    }
    const f = v * (SUN.length - 1);
    const i = Math.floor(f);
    const color = mix(SUN[i], SUN[Math.min(SUN.length - 1, i + 1)], f - i);
    buf.fill(color, y * w + Math.max(0, Math.round(sx - half)), y * w + Math.min(w, Math.round(sx + half)));
  }
}

function renderPixels(s: Scene, buf: Uint32Array, time: number, view: View) {
  const { w, h, glow } = s;
  buf.fill(0);

  for (const c of s.clouds) {
    const span = w + c.w + 16;
    const left = Math.round((((c.x0 + c.speed * time - view.x * c.depth * 3) % span) + span) % span) - c.w - 8;
    for (let cy = 0; cy < c.h; cy++) {
      const y = c.y + cy;
      if (y < 0 || y >= h) continue;
      for (let cx = 0; cx < c.w; cx++) {
        const m = c.mask[cy * c.w + cx];
        const x = left + cx;
        if (!m || x < 0 || x >= w) continue;
        buf[y * w + x] =
          m === 2 ? mix(c.body, RIM, c.rimBase + 0.5 * glow[x]) : m === 3 ? mix(c.body, CLOUD_TOP, 0.14) : c.body;
      }
    }
  }

  if (s.showSun) drawSun(s, buf, time, view);

  for (let n = 0; n < s.ridges.length; n++) {
    const ridge = s.ridges[n];
    const ox = Math.round(-view.x * ridge.depth * 8);
    const oy = Math.round(-view.y * ridge.depth * 2);
    for (let x = 0; x < w; x++) {
      const i = x + MARGIN - ox;
      const top = ridge.top[i] + oy;
      const left = ridge.top[i - 1] + oy;
      const right = ridge.top[i + 1] + oy;
      const rim = mix(ridge.color, ridge.rim, glow[x] * ridge.rimStrength);
      for (let y = Math.max(0, top); y < h; y++) {
        buf[y * w + x] = y === top || y < left || y < right ? rim : ridge.color;
      }
    }

    for (const tree of ridge.trees) {
      const ground = ridge.top[tree.col] + oy;
      const { rows, w: tw, h: th, trunk } = tree.sprite;
      for (let ty = 0; ty < th; ty++) {
        const y = ground - th + ty;
        if (y < 0 || y >= h) continue;
        for (let tx = 0; tx < tw; tx++) {
          const x = tree.col - MARGIN + ox - trunk + tx;
          if (rows[ty][tx] === "#" && x >= 0 && x < w) buf[y * w + x] = ridge.color;
        }
      }
    }

    if (n === 0) {
      for (let y = Math.max(0, s.fogTop); y < Math.min(h, s.fogBottom); y++) {
        const t =
          y < s.horizon ? (y - s.fogTop) / (s.horizon - s.fogTop) : 1 - (y - s.horizon) / (s.fogBottom - s.horizon);
        for (let x = 0; x < w; x++) {
          const i = y * w + x;
          if (buf[i]) buf[i] = mix(buf[i], FOG, t * t * (0.16 + 0.3 * glow[x]));
        }
      }
    }
  }

  for (const f of s.flies) {
    const a = Math.pow(Math.max(0, Math.sin(time * f.blink + f.phase)), 3);
    if (a < 0.05) continue;
    const x = Math.round(f.x + Math.sin(time * 0.35 + f.phase) * 5 - view.x * 8);
    const y = Math.round(f.y + Math.sin(time * 0.5 + f.phase * 1.7) * 2.5);
    if (x < 1 || x >= w - 1 || y < 1 || y >= h - 1) continue;
    const i = y * w + x;
    if (!buf[i]) continue;
    buf[i] = mix(buf[i], FIREFLY, a);
    for (const j of [i - 1, i + 1, i - w, i + w]) if (buf[j]) buf[j] = mix(buf[j], FIREFLY, a * 0.25);
  }
}


function mountHorizonScene() {
  const landscape = undefined, sunX = undefined, wideSunX = undefined, wideSunScale = undefined, wideSunRise = undefined, sun = true;

    const wrap = document.querySelector(".horizon-scene");
    const skyCanvas = document.getElementById("scene-sky");
    const pixelCanvas = document.getElementById("scene-pixels");
    const skyCtx = skyCanvas?.getContext("2d", { alpha: false });
    const pixelCtx = pixelCanvas?.getContext("2d");
    if (!wrap || !skyCanvas || !pixelCanvas || !skyCtx || !pixelCtx) return;

    const preference = window.matchMedia("(prefers-reduced-motion: reduce)");
    let still = preference.matches;
    let visible = true;
    const target = { x: 0, y: 0, sink: 0 };
    const view: View = { x: 0, y: 0, sink: 0 };
    let scene: Scene | null = null;
    let image: ImageData | null = null;
    let buf: Uint32Array | null = null;
    let time = 0;
    let last = 0;
    let raf = 0;

    const draw = () => {
      if (!scene || !image || !buf) return;
      renderSky(skyCtx, scene, time, view);
      renderPixels(scene, buf, time, view);
      pixelCtx.putImageData(image, 0, 0);
      wrap.dataset.ready = "";
    };

    const resize = () => {
      const { width, height } = wrap.getBoundingClientRect();
      if (!width || !height) return;
      const dpr = Math.min(2, window.devicePixelRatio || 1);
      const land = landscape ? height * landscape : clamp(window.innerHeight * 0.3, 180, 320);
      const wide = width >= 1024;
      const x = sunX ?? (wide ? (wideSunX ?? 0.63) : 0.5);
      scene = buildScene(width, height, land, x, wide ? (wideSunScale ?? 1) : 1, wide ? (wideSunRise ?? 0) : 0, sun, dpr);

      skyCanvas.width = Math.round(width * dpr);
      skyCanvas.height = Math.round(height * dpr);
      skyCanvas.style.width = `${width}px`;
      skyCanvas.style.height = `${height}px`;
      skyCtx.setTransform(dpr, 0, 0, dpr, 0, 0);

      pixelCanvas.width = scene.w;
      pixelCanvas.height = scene.h;
      pixelCanvas.style.width = `${scene.w * scene.px}px`;
      pixelCanvas.style.height = `${scene.h * scene.px}px`;
      image = pixelCtx.createImageData(scene.w, scene.h);
      buf = new Uint32Array(image.data.buffer);
      draw();
    };

    const tick = (now: number) => {
      raf = requestAnimationFrame(tick);
      if (now - last < 31) return;
      const dt = last ? Math.min(now - last, 100) / 1000 : 0;
      last = now;
      time += dt;
      const ease = Math.min(1, dt * 3);
      view.x += (target.x - view.x) * ease;
      view.y += (target.y - view.y) * ease;
      view.sink += (target.sink - view.sink) * ease;
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

    const onPointer = (e: PointerEvent) => {
      if (still) return;
      target.x = (e.clientX / window.innerWidth) * 2 - 1;
      target.y = (e.clientY / window.innerHeight) * 2 - 1;
    };
    const onScroll = () => {
      if (!scene || still) return;
      const rect = wrap.getBoundingClientRect();
      target.sink = clamp(-rect.top / rect.height, 0, 1) * scene.sun.r * 0.9;
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(wrap);
    const visibility = new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; visible ? start() : stop(); });
    visibility.observe(wrap);
    {
      window.addEventListener("pointermove", onPointer, { passive: true });
      window.addEventListener("scroll", onScroll, { passive: true });
    }

    const onPreference = () => {
      still = preference.matches;
      if (still) { stop(); target.x = target.y = view.x = view.y = 0; draw(); }
      else start();
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
      visibility.disconnect();
      window.removeEventListener("pointermove", onPointer);
      window.removeEventListener("scroll", onScroll);
    };

}
mountHorizonScene();
})();
