/// The page a blocked Safari tab lands on.
/// Query: `until` (unix seconds), `url` (what was blocked), `n` (attempts so far).
let blockPageHTML = #"""
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<link rel="icon" href="data:,">
<title>Blocked</title>
<style>
  :root {
    color-scheme: light dark;
    --bg: #f5f5f7;
    --text: #1d1d1f;
    --muted: #6e6e73;
    --line: #d2d2d7;
    --accent: #0071e3;
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --bg: #111113;
      --text: #f5f5f7;
      --muted: #98989d;
      --line: #2c2c2e;
      --accent: #2997ff;
    }
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; min-height: 100%; }
  body {
    display: grid;
    place-items: center;
    min-height: 100vh;
    padding: 24px 16px;
    background: var(--bg);
    color: var(--text);
    font: 17px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  main { width: 100%; max-width: 460px; text-align: center; }
  .lock { width: 56px; height: 56px; color: var(--accent); margin-bottom: 20px; }
  h1 { font-size: 34px; line-height: 1.15; letter-spacing: -0.02em; margin: 0 0 10px; font-weight: 700; }
  .left { margin: 0 0 32px; color: var(--muted); font-size: 20px; font-variant-numeric: tabular-nums; }
  .meta { border-top: 1px solid var(--line); padding-top: 18px; color: var(--muted); font-size: 14px; }
  .site { overflow-wrap: anywhere; }
  .open {
    display: inline-block; margin: 0 0 32px; padding: 10px 20px; border-radius: 10px;
    background: var(--accent); color: #fff; text-decoration: none; font-weight: 600;
  }
  [hidden] { display: none !important; }
</style>
</head>
<body>
<main>
  <svg class="lock" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"
       stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect x="4" y="10.5" width="16" height="10.5" rx="2.5"/>
    <path d="M8 10.5V7a4 4 0 0 1 8 0v3.5"/>
  </svg>
  <h1 id="title">Blocked</h1>
  <p class="left" id="left"></p>
  <a class="open" id="open" hidden>Open the page</a>
  <div class="meta">
    <div class="site" id="site"></div>
    <div id="tries"></div>
  </div>
</main>
<script>
  const query = new URLSearchParams(location.search);
  const until = Number(query.get("until")) * 1000;
  const blocked = query.get("url") || "";
  const tries = Number(query.get("n")) || 0;

  const pad = (n) => String(n).padStart(2, "0");
  const plural = (n, one, other) => (n === 1 ? one : other);

  function endLabel() {
    const end = new Date(until);
    const time = pad(end.getHours()) + ":" + pad(end.getMinutes());
    const tomorrow = new Date();
    tomorrow.setDate(tomorrow.getDate() + 1);
    if (end.toDateString() === new Date().toDateString()) return time;
    if (end.toDateString() === tomorrow.toDateString()) return "tomorrow, " + time;
    return end.toLocaleDateString("en-US", { month: "short", day: "numeric" }) + ", " + time;
  }

  const $ = (id) => document.getElementById(id);
  $("site").textContent = blocked.replace(/^https?:\/\/(www\.)?/, "");
  if (tries > 0) {
    $("tries").textContent = tries + " " + plural(tries, "attempt", "attempts") + " blocked so far";
  }

  function render() {
    const left = Math.ceil((until - Date.now()) / 1000);
    if (!until) return;
    if (left > 0) {
      const d = Math.floor(left / 86400), h = Math.floor(left / 3600) % 24;
      const m = Math.floor(left / 60) % 60, s = left % 60;
      $("title").textContent = "Blocked until " + endLabel();
      $("left").textContent = (d ? d + "d " : "") + (d || h ? h + ":" + pad(m) : m) + ":" + pad(s) + " left";
      return;
    }
    clearInterval(timer);
    $("title").textContent = "Block is over";
    $("left").textContent = "You can go back now";
    document.title = "Block is over";
    if (/^https?:\/\//.test(blocked)) {
      $("open").href = blocked;
      $("open").hidden = false;
    }
  }

  const timer = setInterval(render, 1000);
  render();
</script>
</body>
</html>
"""#
