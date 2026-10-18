/// The page a blocked Safari tab lands on: murky water that settles. Trying the site stirred it up,
/// and it clears if you leave it alone; more attempts stir it harder. A small find waits in the sand.
/// Query: `until` (unix seconds), `url` (what was blocked), `n` (attempts so far, this one included).
let blockPageHTML = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" href="data:,">
<title>Blocked</title>
<style>
  :root { color-scheme: dark; --soft: rgba(255,255,255,.82); --faint: rgba(255,255,255,.55); --shadow: 0 1px 12px rgba(0,20,30,.6);
    --sf: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; --mono: ui-monospace, "SF Mono", Menlo, monospace; }
  * { box-sizing: border-box; }
  html, body { margin: 0; height: 100%; }
  body { background: #0C3440; color: #fff; font: 17px/1.45 var(--sf); -webkit-font-smoothing: antialiased; overflow: hidden; }
  #gl { position: fixed; inset: 0; width: 100%; height: 100%; display: block; touch-action: none; cursor: crosshair; }
  #gl.grab { cursor: pointer; }
  /* The message is drawn into the water; this text is for VoiceOver, and becomes the page without WebGL2. */
  main { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
  .plain { background: linear-gradient(#2C8296, #0C3440); }
  .plain #gl { display: none; }
  .plain main { position: fixed; inset: 0; width: auto; height: auto; clip-path: none; white-space: normal; display: grid; place-content: center; text-align: center; padding: 24px; }
  main h1 { margin: 0 0 8px; font-size: clamp(32px, 6vw, 64px); line-height: 1.1; letter-spacing: -.03em; font-weight: 700; }
  main p { margin: 0; color: var(--soft); font-variant-numeric: tabular-nums; overflow-wrap: anywhere; }
  .brand { position: fixed; left: 22px; top: calc(18px + env(safe-area-inset-top, 0px)); display: flex; align-items: center; gap: 8px; font-size: 13px; font-weight: 600; color: var(--soft); pointer-events: none; text-shadow: var(--shadow); }
  .brand svg { width: 14px; height: 14px; fill: currentColor; }
  .finds { position: fixed; right: 22px; top: calc(18px + env(safe-area-inset-top, 0px)); font: 600 11px/1 var(--mono); letter-spacing: .1em; color: rgba(200,240,240,.75); pointer-events: none; text-shadow: var(--shadow); }
  .dock { position: fixed; left: 0; right: 0; bottom: calc(26px + env(safe-area-inset-bottom, 0px)); display: grid; justify-items: center; gap: 12px; padding: 0 16px; pointer-events: none; }
  .line { font-size: 13.5px; color: var(--faint); text-align: center; text-shadow: var(--shadow); min-height: 1.4em; font-variant-numeric: tabular-nums; }
  .open { pointer-events: auto; font-size: 13px; font-weight: 600; padding: 8px 16px; border-radius: 999px; background: rgba(255,255,255,.92); color: #0B2D36; text-decoration: none; }
  .open:hover { background: #fff; }
  .open:focus-visible { outline: 2px solid rgba(160,230,235,.9); outline-offset: 2px; }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<canvas id="gl" aria-hidden="true"></canvas>
<main>
  <h1 id="title">Blocked</h1>
  <p id="sub"></p>
</main>
<div class="brand"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 10V7.5a5 5 0 0 1 10 0V10h.5A2.5 2.5 0 0 1 20 12.5v7a2.5 2.5 0 0 1-2.5 2.5h-11A2.5 2.5 0 0 1 4 19.5v-7A2.5 2.5 0 0 1 6.5 10H7Zm2 0h6V7.5a3 3 0 0 0-6 0V10Z"/></svg>FocusLock</div>
<div class="finds" id="finds" hidden></div>
<div class="dock">
  <div class="line" id="line"></div>
  <a class="open" id="open" hidden>Open the page</a>
</div>
<script>
// Trying the site stirred the water up. Leave it alone and the silt sinks until the message underneath reads
// again. Stable-fluids simulation (advect, curl, pressure) on WebGL2; plain text where WebGL2 isn't available.
(() => {
  const $ = (id) => document.getElementById(id);
  const RM = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const query = new URLSearchParams(location.search);
  const until = Number(query.get("until")) * 1000;
  const blocked = query.get("url") || "";
  // Attempts in this block, this one included.
  const tries = Math.max(1, Number(query.get("n")) || 1);
  const shown = blocked.replace(/^https?:\/\/(www\.)?/, "").replace(/\/$/, "");
  const site = shown.length > 36 ? shown.slice(0, 35) + "…" : shown;
  const host = shown.split(/[/?#]/)[0] || "the site";

  const pad = (n) => String(n).padStart(2, "0");
  const ORD = ["", "First", "Second", "Third", "Fourth", "Fifth"], ord = (n) => ORD[n] || `${n}th`;

  function endLabel() {
    const end = new Date(until);
    const time = pad(end.getHours()) + ":" + pad(end.getMinutes());
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    if (end.toDateString() === new Date().toDateString()) return time;
    if (end.toDateString() === tomorrow.toDateString()) return "tomorrow, " + time;
    return end.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + ", " + time;
  }

  // What the page says right now. Drawn into the water, and kept as real text for VoiceOver and the fallback.
  function state() {
    if (!until) return { over: false, title: "Blocked", sub: site, left: "" };
    const left = Math.ceil((until - Date.now()) / 1000);
    if (left <= 0) return { over: true, title: "Block is over", sub: "You can go back now", left: "" };
    const d = Math.floor(left / 86400), h = Math.floor(left / 3600) % 24, m = Math.floor(left / 60) % 60, s = left % 60;
    const time = (d ? d + "d " : "") + (d || h ? h + ":" + pad(m) : m) + ":" + pad(s);
    return { over: false, title: "Blocked until " + endLabel(), sub: site ? `${time} left  ·  ${site}` : `${time} left`, left: time };
  }
  let now = state(), onTick = () => {};
  function render() {
    now = state();
    $("title").textContent = now.title;
    $("sub").textContent = now.sub;
    document.title = now.over ? "Block is over" : "Blocked";
    if (now.over && /^https?:\/\//.test(blocked)) {
      $("open").href = blocked;
      $("open").textContent = `Open ${host}`;
      $("open").hidden = false;
    }
    onTick();
  }
  render();
  setInterval(render, 1000);

  const canvas = $("gl");
  const gl = canvas.getContext("webgl2", { alpha: false, antialias: false, depth: false, premultipliedAlpha: false });
  const fail = () => document.body.classList.add("plain");
  if (!gl || !gl.getExtension("EXT_color_buffer_float")) return fail();

  // ---------- plumbing ----------
  const VS = `#version 300 es
    in vec2 aPos; out vec2 vUv; out vec2 vL; out vec2 vR; out vec2 vT; out vec2 vB; uniform vec2 uTexel;
    void main(){ vUv = aPos * 0.5 + 0.5; vL = vUv - vec2(uTexel.x, 0.0); vR = vUv + vec2(uTexel.x, 0.0); vT = vUv + vec2(0.0, uTexel.y); vB = vUv - vec2(0.0, uTexel.y); gl_Position = vec4(aPos, 0.0, 1.0); }`;
  const head = "#version 300 es\nprecision highp float; precision highp sampler2D;\nin vec2 vUv; in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 o;\n";
  function program(fs) {
    const mk = (t, s) => { const sh = gl.createShader(t); gl.shaderSource(sh, s); gl.compileShader(sh); if (!gl.getShaderParameter(sh, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(sh)); return sh; };
    const p = gl.createProgram(); gl.attachShader(p, mk(gl.VERTEX_SHADER, VS)); gl.attachShader(p, mk(gl.FRAGMENT_SHADER, head + fs));
    gl.bindAttribLocation(p, 0, "aPos"); gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p));
    const u = {}; const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) { const name = gl.getActiveUniform(p, i).name; u[name] = gl.getUniformLocation(p, name); }
    return { p, u };
  }
  let P;
  try {
    P = {
      splat: program(`uniform sampler2D uTarget; uniform float uAspect, uRadius; uniform vec3 uColor; uniform vec2 uPoint;
        void main(){ vec2 p = vUv - uPoint; p.x *= uAspect; vec3 s = exp(-dot(p, p) / uRadius) * uColor; o = vec4(texture(uTarget, vUv).xyz + s, 1.0); }`),
      advect: program(`uniform sampler2D uVel, uSrc; uniform vec2 uTexel; uniform float uDt, uDiss; uniform vec2 uDrift;
        void main(){ vec2 coord = vUv - uDt * texture(uVel, vUv).xy * uTexel - uDt * uDrift; o = uDiss * texture(uSrc, coord); }`),
      curl: program(`uniform sampler2D uVel;
        void main(){ float L = texture(uVel, vL).y, R = texture(uVel, vR).y, T = texture(uVel, vT).x, B = texture(uVel, vB).x; o = vec4(0.5 * (R - L - T + B), 0.0, 0.0, 1.0); }`),
      vort: program(`uniform sampler2D uVel, uCurl; uniform float uCurlAmt, uDt;
        void main(){ float L = texture(uCurl, vL).x, R = texture(uCurl, vR).x, T = texture(uCurl, vT).x, B = texture(uCurl, vB).x, C = texture(uCurl, vUv).x;
          vec2 f = 0.5 * vec2(abs(T) - abs(B), abs(R) - abs(L)); f /= length(f) + 0.0001; f *= uCurlAmt * C; f.y *= -1.0;
          o = vec4(texture(uVel, vUv).xy + f * uDt, 0.0, 1.0); }`),
      div: program(`uniform sampler2D uVel;
        void main(){ float L = texture(uVel, vL).x, R = texture(uVel, vR).x, T = texture(uVel, vT).y, B = texture(uVel, vB).y; vec2 C = texture(uVel, vUv).xy;
          if (vL.x < 0.0) L = -C.x; if (vR.x > 1.0) R = -C.x; if (vT.y > 1.0) T = -C.y; if (vB.y < 0.0) B = -C.y; o = vec4(0.5 * (R - L + T - B), 0.0, 0.0, 1.0); }`),
      clear: program(`uniform sampler2D uTex; uniform float uVal; void main(){ o = uVal * texture(uTex, vUv); }`),
      press: program(`uniform sampler2D uP, uDiv;
        void main(){ float L = texture(uP, vL).x, R = texture(uP, vR).x, T = texture(uP, vT).x, B = texture(uP, vB).x; o = vec4((L + R + B + T - texture(uDiv, vUv).x) * 0.25, 0.0, 0.0, 1.0); }`),
      grad: program(`uniform sampler2D uP, uVel;
        void main(){ float L = texture(uP, vL).x, R = texture(uP, vR).x, T = texture(uP, vT).x, B = texture(uP, vB).x; o = vec4(texture(uVel, vUv).xy - vec2(R - L, T - B), 0.0, 1.0); }`),
      show: program(`uniform sampler2D uDye, uText, uVel; uniform float uTime; uniform vec2 uRes, uDyeTexel;
        float h21(vec2 p){ p = fract(p * vec2(233.34, 851.73)); p += dot(p, p + 23.45); return fract(p.x * p.y); }
        float caustic(vec2 p, float t){ vec2 i = p; float c = 1.0; for (int n = 0; n < 4; n++){ float tt = t * (1.0 - (3.5 / float(n + 1))); i = p + vec2(cos(tt - i.x) + sin(tt + i.y), sin(tt - i.y) + cos(tt + i.x)); c += 1.0 / length(vec2(p.x / (sin(i.x + tt) / 0.005), p.y / (cos(i.y + tt) / 0.005))); } c /= 4.0; c = 1.17 - pow(c, 1.4); return clamp(pow(abs(c), 8.0), 0.0, 1.0); }
        void main(){
          vec2 uv = vUv; float asp = uRes.x / uRes.y;
          vec2 v = texture(uVel, uv).xy, wob = clamp(v * 0.00005, -0.012, 0.012);
          vec3 col = mix(vec3(0.05, 0.22, 0.27), vec3(0.18, 0.52, 0.58), pow(uv.y, 1.2));
          col += vec3(0.9, 1.0, 1.0) * exp(-length((uv - vec2(0.62, 1.12)) * vec2(asp * 0.6, 1.0)) * 3.0) * 0.22;
          float rays = 0.0; for (int k = 0; k < 5; k++){ float x = 0.12 + float(k) * 0.2 + sin(uTime * 0.15 + float(k)) * 0.03; rays += smoothstep(0.05, 0.0, abs(uv.x - x - (1.0 - uv.y) * 0.18)) * (0.5 + 0.5 * sin(uTime * 0.6 + float(k) * 2.0)); }
          col += vec3(0.75, 0.95, 0.95) * rays * 0.05 * uv.y;
          float floorY = 0.16 + sin(uv.x * 7.0) * 0.008 + sin(uv.x * 19.0 + 1.0) * 0.004;
          if (uv.y < floorY){
            vec2 sp = vec2((uv.x + wob.x) * asp, uv.y + wob.y) * 6.0;
            vec3 sand = mix(vec3(0.36, 0.40, 0.34), vec3(0.50, 0.52, 0.42), sin(sp.x * 2.2 + sin(sp.y * 3.0)) * 0.5 + 0.5);
            sand += vec3(0.6, 0.85, 0.8) * caustic(sp * 0.9, uTime * 0.35) * 0.25;
            sand *= 0.75 + 0.25 * (uv.y / floorY);
            col = mix(col, sand, smoothstep(floorY, floorY - 0.01, uv.y));
          }
          vec2 tuv = uv + wob + vec2(sin(uv.y * 38.0 + uTime * 1.2), cos(uv.x * 26.0 + uTime * 0.9)) * 0.0016;
          vec4 tx = texture(uText, tuv);
          col = mix(col, tx.rgb, tx.a * 0.96);
          vec2 e = uDyeTexel * 5.0;
          float d = 0.0; for (int j = -2; j <= 2; j++) for (int k = -2; k <= 2; k++) d += texture(uDye, uv + vec2(float(j), float(k)) * e).r; d /= 25.0;
          float dUp = texture(uDye, uv + vec2(0.0, uDyeTexel.y * 14.0)).r;
          float shade = clamp(1.0 + (d - dUp) * 0.6, 0.88, 1.12);
          vec3 silt = mix(vec3(0.27, 0.32, 0.30), vec3(0.58, 0.62, 0.55), clamp(uv.y * 1.05, 0.0, 1.0)) * shade;
          col += vec3(0.8, 1.0, 1.0) * min(length(v) * 0.00012, 0.03);
          float a = 1.0 - exp(-max(d, 0.0) * 1.6);
          col = mix(col, silt, clamp(a, 0.0, 0.92));
          vec2 vq = uv - 0.5; col *= 1.0 - 0.55 * dot(vq, vq);
          col += (h21(gl_FragCoord.xy + fract(uTime) * 13.0) - 0.5) * 0.018;
          o = vec4(col, 1.0);
        }`),
    };
  } catch (e) { console.error(e); return fail(); }

  const quad = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0); gl.enableVertexAttribArray(0);

  function fbo(w, h) {
    const tex = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA16F, w, h, 0, gl.RGBA, gl.HALF_FLOAT, null);
    const fb = gl.createFramebuffer(); gl.bindFramebuffer(gl.FRAMEBUFFER, fb); gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
    gl.viewport(0, 0, w, h); gl.clearColor(0, 0, 0, 1); gl.clear(gl.COLOR_BUFFER_BIT);
    return { tex, fb, w, h };
  }
  const dbl = (w, h) => { let a = fbo(w, h), b = fbo(w, h); return { get r() { return a; }, get w() { return b; }, swap() { [a, b] = [b, a]; }, width: w, height: h }; };
  let unit = 0;
  const bindTex = (prog, name, f) => { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, f.tex || f); gl.uniform1i(prog.u[name], unit); unit++; };
  const run = (prog, target, setup) => {
    gl.useProgram(prog.p); unit = 0; setup(prog);
    if (target) { gl.bindFramebuffer(gl.FRAMEBUFFER, target.fb); gl.viewport(0, 0, target.w, target.h); }
    else { gl.bindFramebuffer(gl.FRAMEBUFFER, null); gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight); }
    gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
  };

  let vel, dye, divF, curlF, pres, simW, simH, dyeW, dyeH;
  function alloc() {
    const asp = canvas.width / canvas.height;
    simH = 128; simW = Math.round(128 * asp); dyeH = 512; dyeW = Math.round(512 * asp);
    vel = dbl(simW, simH); dye = dbl(dyeW, dyeH); pres = dbl(simW, simH); divF = fbo(simW, simH); curlF = fbo(simW, simH);
  }



  // ---------- finds: one small thing in the sand each time, kept by the app so the menu shows them too ----------
  let finds = [];
  const report = (kind) => fetch(`/find?kind=${encodeURIComponent(kind)}`, { method: "POST" }).catch(() => {});
  (async () => {
    // Earlier versions kept finds in this browser; hand them to the app once.
    try {
      const old = JSON.parse(localStorage.getItem("fl-finds") || "[]");
      if (old.length) { await Promise.all(old.map(report)); localStorage.removeItem("fl-finds"); }
    } catch (e) { /* storage unavailable */ }
    try { finds = await (await fetch("/finds")).json(); } catch (e) { /* app unreachable */ }
    renderFinds();
  })();
  // More tries stir it up harder, and it takes longer to settle.
  const strength = () => Math.min(1.6, 0.75 + 0.25 * (tries - 1));
  const clearAfter = () => 6 + (strength() - 0.75) * 8;
  const floorAt = (x) => 0.16 + Math.sin(x * 7) * 0.008 + Math.sin(x * 19 + 1) * 0.004;

  const KINDS = {
    scallop: "a scallop shell", glass: "a piece of sea glass", stone: "a smooth stone",
    dollar: "a sand dollar", snail: "a small snail shell", star: "a starfish",
  };
  const kinds = Object.keys(KINDS), kind = kinds[Math.floor(Math.random() * kinds.length)];
  const fx = Math.random() < 0.5 ? 0.1 + Math.random() * 0.22 : 0.68 + Math.random() * 0.22;
  const find = { kind, x: fx, y: floorAt(fx) - 0.035, rot: (Math.random() - 0.5) * 0.8, picked: false, hover: false };

  function drawFind(c, f, x, y, s) {
    c.save(); c.translate(x, y);
    c.fillStyle = "rgba(8,30,32,.35)"; c.filter = `blur(${s * 0.12}px)`; c.beginPath(); c.ellipse(s * 0.06, s * 0.42, s * 0.78, s * 0.2, 0, 0, Math.PI * 2); c.fill(); c.filter = "none";
    if (f.hover) { const g = c.createRadialGradient(0, 0, 0, 0, 0, s * 1.6); g.addColorStop(0, "rgba(225,255,250,.42)"); g.addColorStop(1, "rgba(225,255,250,0)"); c.fillStyle = g; c.beginPath(); c.arc(0, 0, s * 1.6, 0, Math.PI * 2); c.fill(); c.translate(0, -s * 0.08); }
    c.rotate(f.rot); if (f.hover) { c.scale(1.08, 1.08); c.shadowColor = "rgba(230,255,250,.75)"; c.shadowBlur = s * 0.7; }
    const P = Math.PI;
    if (f.kind === "scallop") {
      const g = c.createLinearGradient(0, -s * 0.5, 0, s * 0.35); g.addColorStop(0, "#F4E8D6"); g.addColorStop(1, "#D2B693");
      c.fillStyle = g; c.beginPath(); c.moveTo(0, s * 0.35); c.arc(0, s * 0.35, s * 0.78, P * 1.2, P * 1.8); c.closePath(); c.fill();
      c.shadowBlur = 0; c.strokeStyle = "rgba(140,100,70,.35)"; c.lineWidth = s * 0.035;
      for (let i = -3; i <= 3; i++) { const a = P * 1.5 + i * 0.1 * P; c.beginPath(); c.moveTo(0, s * 0.35); c.lineTo(Math.cos(a) * s * 0.74, s * 0.35 + Math.sin(a) * s * 0.74); c.stroke(); }
      c.fillStyle = "#CDAF8A"; c.fillRect(-s * 0.2, s * 0.26, s * 0.4, s * 0.12);
    } else if (f.kind === "glass") {
      c.fillStyle = "rgba(150,222,190,.88)"; c.beginPath(); c.moveTo(-s * 0.5, -s * 0.05); c.quadraticCurveTo(-s * 0.4, -s * 0.38, 0, -s * 0.32); c.quadraticCurveTo(s * 0.5, -s * 0.3, s * 0.48, s * 0.05); c.quadraticCurveTo(s * 0.4, s * 0.3, -s * 0.05, s * 0.28); c.quadraticCurveTo(-s * 0.55, s * 0.25, -s * 0.5, -s * 0.05); c.fill();
      c.shadowBlur = 0; c.fillStyle = "rgba(255,255,255,.45)"; c.beginPath(); c.ellipse(-s * 0.15, -s * 0.12, s * 0.16, s * 0.06, -0.3, 0, P * 2); c.fill();
    } else if (f.kind === "stone") {
      const g = c.createRadialGradient(-s * 0.2, -s * 0.2, s * 0.05, 0, 0, s * 0.7); g.addColorStop(0, "#B9BCB3"); g.addColorStop(1, "#666A63");
      c.fillStyle = g; c.beginPath(); c.ellipse(0, 0, s * 0.62, s * 0.38, 0, 0, P * 2); c.fill();
    } else if (f.kind === "dollar") {
      c.fillStyle = "#EEE6D4"; c.beginPath(); c.arc(0, 0, s * 0.5, 0, P * 2); c.fill();
      c.shadowBlur = 0; c.fillStyle = "rgba(160,135,100,.45)";
      for (let i = 0; i < 5; i++) { const a = i / 5 * P * 2 - P / 2; c.beginPath(); c.ellipse(Math.cos(a) * s * 0.2, Math.sin(a) * s * 0.2, s * 0.15, s * 0.05, a, 0, P * 2); c.fill(); }
    } else if (f.kind === "snail") {
      const g = c.createRadialGradient(-s * 0.1, -s * 0.1, 0, 0, 0, s * 0.55); g.addColorStop(0, "#EBD8B8"); g.addColorStop(1, "#BE9C72");
      c.fillStyle = g; c.beginPath(); c.arc(0, 0, s * 0.45, 0, P * 2); c.fill();
      c.shadowBlur = 0; c.strokeStyle = "rgba(110,75,45,.5)"; c.lineWidth = s * 0.05; c.beginPath();
      for (let t = 0; t < P * 4; t += 0.1) { const r = s * 0.04 + s * 0.4 * t / (P * 4); c.lineTo(Math.cos(t) * r, Math.sin(t) * r); } c.stroke();
    } else {
      c.fillStyle = "#D99470"; c.lineJoin = "round"; c.strokeStyle = "#D99470"; c.lineWidth = s * 0.12; c.beginPath();
      for (let i = 0; i < 10; i++) { const a = i / 10 * P * 2 - P / 2, r = i % 2 ? s * 0.2 : s * 0.55; c.lineTo(Math.cos(a) * r, Math.sin(a) * r); } c.closePath(); c.fill(); c.stroke();
      c.shadowBlur = 0; c.fillStyle = "rgba(255,230,210,.35)"; for (let i = 0; i < 5; i++) { const a = i / 5 * P * 2 - P / 2; c.beginPath(); c.arc(Math.cos(a) * s * 0.25, Math.sin(a) * s * 0.25, s * 0.04, 0, P * 2); c.fill(); }
    }
    c.restore();
  }


  // ---------- the message (and the find), drawn into the water ----------
  const textCv = document.createElement("canvas"), tctx = textCv.getContext("2d");
  const textTex = gl.createTexture();
  const font = (weight, px, face) => `${weight} ${px}px ${face || '-apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", sans-serif'}`;
  function drawText() {
    const w = canvas.width, h = canvas.height, d = w / innerWidth;
    textCv.width = w; textCv.height = h; tctx.clearRect(0, 0, w, h);
    if (!find.picked) drawFind(tctx, find, find.x * w, (1 - find.y) * h, 30 * d);
    let big = Math.min(96, Math.max(34, innerWidth * 0.072)) * d;
    tctx.font = font(700, big);
    const fit = (w * 0.9) / tctx.measureText(now.title).width;
    if (fit < 1) big *= fit;
    const cy = h * 0.4;
    tctx.textAlign = "center"; tctx.textBaseline = "middle"; tctx.fillStyle = "#fff";
    tctx.shadowColor = "rgba(0,25,35,.35)"; tctx.shadowBlur = 30 * d;
    tctx.font = font(700, big);
    tctx.fillText(now.title, w / 2, cy);
    tctx.font = font(500, Math.max(15 * d, big * 0.2), '-apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif'); tctx.fillStyle = "rgba(255,255,255,.85)";
    tctx.fillText(now.sub, w / 2, cy + big * 0.85);
    tctx.font = font(600, Math.max(11 * d, big * 0.14), 'ui-monospace, "SF Mono", Menlo, monospace'); tctx.fillStyle = "rgba(160,225,235,.8)";
    tctx.fillText(now.over ? "ALL CLEAR" : `${ord(tries).toUpperCase()} TRY`, w / 2, cy - big * 0.95);
    tctx.shadowBlur = 0;
    gl.bindTexture(gl.TEXTURE_2D, textTex); gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, textCv);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR); gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false);
  }
  onTick = drawText;

  // ---------- splats ----------
  function splat(x, y, dx, dy, silt, radius) {
    const asp = canvas.width / canvas.height;
    run(P.splat, vel.w, (p) => { bindTex(p, "uTarget", vel.r.tex); gl.uniform1f(p.u.uAspect, asp); gl.uniform2f(p.u.uPoint, x, y); gl.uniform3f(p.u.uColor, dx, dy, 0); gl.uniform1f(p.u.uRadius, radius / 100); });
    vel.swap();
    if (silt > 0) {
      run(P.splat, dye.w, (p) => { bindTex(p, "uTarget", dye.r.tex); gl.uniform1f(p.u.uAspect, asp); gl.uniform2f(p.u.uPoint, x, y); gl.uniform3f(p.u.uColor, silt, silt, silt); gl.uniform1f(p.u.uRadius, radius / 100); });
      dye.swap();
    }
  }
  let lastStir = 0;
  function stirUp(k = 1) {
    for (let i = 0; i < 44; i++) {
      const x = 0.04 + Math.random() * 0.92, y = 0.1 + Math.random() * 0.7;
      splat(x, y, (Math.random() - 0.5) * 500 * k, (Math.random() - 0.3) * 260 * k, (0.38 + Math.random() * 0.35) * k, 0.9 + Math.random() * 1.6);
    }
    lastStir = time;
  }
  const kickSand = (x, up, silt, r) => splat(x, floorAt(x) + 0.004, (Math.random() - 0.5) * 120, up, silt, r);


  // ---------- step ----------
  let time = 0;
  function step(dt) {
    const texel = [1 / simW, 1 / simH], diss = 0.9952 + Math.min(0.0012, (tries - 1) * 0.0004);
    gl.disable(gl.BLEND);
    run(P.curl, curlF, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uVel", vel.r.tex); });
    run(P.vort, vel.w, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uVel", vel.r.tex); bindTex(p, "uCurl", curlF.tex); gl.uniform1f(p.u.uCurlAmt, 5); gl.uniform1f(p.u.uDt, dt); }); vel.swap();
    run(P.div, divF, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uVel", vel.r.tex); });
    run(P.clear, pres.w, (p) => { bindTex(p, "uTex", pres.r.tex); gl.uniform1f(p.u.uVal, 0.8); }); pres.swap();
    for (let i = 0; i < 22; i++) { run(P.press, pres.w, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uP", pres.r.tex); bindTex(p, "uDiv", divF.tex); }); pres.swap(); }
    run(P.grad, vel.w, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uP", pres.r.tex); bindTex(p, "uVel", vel.r.tex); }); vel.swap();
    run(P.advect, vel.w, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uVel", vel.r.tex); bindTex(p, "uSrc", vel.r.tex); gl.uniform1f(p.u.uDt, dt); gl.uniform1f(p.u.uDiss, Math.pow(0.985, dt * 60)); gl.uniform2f(p.u.uDrift, 0, 0); }); vel.swap();
    run(P.advect, dye.w, (p) => { gl.uniform2f(p.u.uTexel, ...texel); bindTex(p, "uVel", vel.r.tex); bindTex(p, "uSrc", dye.r.tex); gl.uniform1f(p.u.uDt, dt); gl.uniform1f(p.u.uDiss, Math.pow(diss, dt * 60)); gl.uniform2f(p.u.uDrift, 0, -0.028); }); dye.swap();
  }
  function show() {
    run(P.show, null, (p) => { bindTex(p, "uDye", dye.r.tex); bindTex(p, "uText", textTex); bindTex(p, "uVel", vel.r.tex); gl.uniform1f(p.u.uTime, time); gl.uniform2f(p.u.uRes, canvas.width, canvas.height); gl.uniform2f(p.u.uDyeTexel, 1 / dyeW, 1 / dyeH); });
  }


  // ---------- pointer: a hand in the water ----------
  const ptr = { x: 0, y: 0, down: false, has: false };
  const toUv = (e) => { const r = canvas.getBoundingClientRect(); return [(e.clientX - r.left) / r.width, 1 - (e.clientY - r.top) / r.height]; };
  const pickable = () => !now.over && find && !find.picked && time - lastStir > clearAfter();
  const overFind = (cx, cy) => find && Math.hypot(cx - find.x * innerWidth, cy - (1 - find.y) * innerHeight) < 30;
  function setHover(on) { if (find && find.hover !== on) { find.hover = on; canvas.classList.toggle("grab", on); drawText(); } }
  canvas.addEventListener("pointermove", (e) => {
    const [x, y] = toUv(e);
    if (ptr.has) {
      const dx = (x - ptr.x) * canvas.width, dy = (y - ptr.y) * canvas.height, sp = Math.hypot(dx, dy);
      if (sp > 0.5) {
        // slow hands leave a clear wake; fast ones lift silt
        const k = ptr.down ? 1 : 0.35, silt = ptr.down ? Math.min(0.5, sp * 0.004) : Math.min(0.3, Math.max(0, sp - 10) * 0.003) * k;
        splat(x, y, dx * 6 * k, dy * 6 * k, silt, ptr.down ? 0.5 : 0.25);
        if (silt > 0.02) lastStir = time;
        // close to the bottom, a quick move kicks up sand
        if (y < floorAt(x) + 0.05 && sp * k > 5) { kickSand(x, 260 + sp * 6 * k, Math.min(0.45, sp * 0.006) * k, 0.6); lastStir = time; }
      }
    }
    ptr.x = x; ptr.y = y; ptr.has = true;
    setHover(pickable() && overFind(e.clientX, e.clientY));
  });
  canvas.addEventListener("pointerdown", (e) => {
    const [x, y] = toUv(e);
    if (pickable() && overFind(e.clientX, e.clientY)) return pickUp();
    ptr.down = true; canvas.setPointerCapture(e.pointerId);
    if (y < floorAt(x) + 0.015) {
      // on the sand: a cloud of sand
      kickSand(x, 650, 1.0, 1.3); splat(x - 0.02, floorAt(x), -220, 260, 0.4, 0.7); splat(x + 0.02, floorAt(x), 220, 260, 0.4, 0.7);
      lastStir = time;
    } else {
      // in the water: a soft swirl
      splat(x, y, 0, 220, 0.04, 0.35);
    }
  });
  canvas.addEventListener("pointerup", () => { ptr.down = false; });
  canvas.addEventListener("pointerleave", () => { ptr.has = false; setHover(false); });

  function pickUp() {
    find.picked = true; setHover(false); finds.push(find.kind); report(find.kind);
    splat(find.x, find.y, 0, 200, 0.12, 0.5);
    toast(`You found ${KINDS[find.kind]}. ${finds.length === 1 ? "Your first find." : `${finds.length} finds so far.`}`, 6);
    renderFinds(); drawText();
  }
  function renderFinds() { const el = $("finds"); el.hidden = !finds.length; el.textContent = `FINDS · ${finds.length}`; }
  renderFinds();


  let toastMsg = "", toastUntil = 0;
  const toast = (s, sec) => { toastMsg = s; toastUntil = time + sec; };

  // ---------- resize + loop ----------
  function resize() {
    const d = Math.min(devicePixelRatio || 1, 2), w = Math.round(innerWidth * d), h = Math.round(innerHeight * d);
    if (canvas.width === w && canvas.height === h) return;
    const first = !vel; canvas.width = w; canvas.height = h; if (first) alloc(); drawText(); if (first) stirUp(RM ? 0.4 : strength());
  }
  addEventListener("resize", resize); resize();

  const line = $("line");
  const say = (s) => { if (line.textContent !== s) line.textContent = s; };
  // The line stays quiet; it only speaks up when you pick something out of the sand.
  const message = () => (time < toastUntil ? toastMsg : "");

  let last = performance.now();
  function frame(stamp) {
    // The first frame's timestamp can predate `last`.
    const dt = Math.max(0, Math.min(1 / 30, (stamp - last) / 1000)); last = stamp; time += dt;
    step(dt); show();
    say(message());
    requestAnimationFrame(frame);
  }
  // For screenshots: #t=SECONDS lets the water settle first; #hover lights up the find.
  const qt = location.hash.match(/t=([\d.]+)/);
  if (qt) for (let i = 0; i < +qt[1] * 60; i++) { time += 1 / 60; step(1 / 60); }
  if (/hover/.test(location.hash)) setHover(true);
  requestAnimationFrame(frame);
})();
</script>
</body>
</html>
"""#
