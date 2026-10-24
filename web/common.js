// Small helpers shared by the pages (load before the page scripts).
(() => {
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  // Count a number up from 0; `fmt` formats each frame.
  function countUp(el, to, ms = 900, fmt = (v) => Math.round(v)) {
    const t0 = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - t0) / ms);
      el.textContent = fmt(to * ease(t));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
  const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));
  // API base: same origin when served by the Worker; for local work (python3 -m http.server) add
  // ?api=https://eczema-twin-live.zhongzhenyu190.workers.dev to use the deployed relay.
  const API = (new URLSearchParams(location.search).get("api") || "").replace(/\/$/, "");
  const api = (path) => API + path;
  const wsUrl = (path) => API ? API.replace(/^http/, "ws") + path : `${location.protocol === "https:" ? "wss:" : "ws:"}//${location.host}${path}`;
  window.twinUI = { ease, countUp, esc, api, wsUrl, sleep: (ms) => new Promise((r) => setTimeout(r, ms)) };
})();
