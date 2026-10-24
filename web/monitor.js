// Eczema Twin · big-screen scratch monitor.
// Live data: WebSocket /api/live (batches from the Apple Watch via the Worker).
// Keys: 1-4 pages · F fullscreen · D demo simulation on/off · R reset counters.
(() => {
  const $ = (s) => document.querySelector(s);
  const RATE = 25;                 // samples per second sent by the watch
  const PX_PER_SAMPLE = 4;         // sweep speed: 100 px per second

  // ---------- pages ----------
  const names = { monitor: "SCRATCH MONITOR", night: "LAST NIGHT", history: "HISTORY", claude: "CLAUDE" };
  function show(page) {
    document.querySelectorAll(".page").forEach((p) => p.classList.toggle("on", p.id === "p-" + page));
    document.querySelectorAll(".tabs button").forEach((b) => b.classList.toggle("on", b.dataset.page === page));
    $("#pageName").textContent = names[page] || "";
    window.dispatchEvent(new CustomEvent("twin:page", { detail: page }));
  }
  document.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => show(b.dataset.page)));
  window.twinShow = show;

  // ---------- clock ----------
  setInterval(() => { $("#clock").textContent = new Date().toLocaleTimeString([], { hour12: false }); }, 500);

  // ---------- sound ----------
  let audio = null;
  function enableSound() { if (!audio) { audio = new (window.AudioContext || window.webkitAudioContext)(); } $("#sound").classList.add("off"); }
  document.addEventListener("pointerdown", enableSound, { once: true });
  $("#sound").addEventListener("click", enableSound);
  function beep(freq = 1046, dur = 0.09, vol = 0.18, when = 0) {
    if (!audio) return;
    const t = audio.currentTime + when;
    const o = audio.createOscillator(), g = audio.createGain();
    o.type = "sine"; o.frequency.value = freq;
    g.gain.setValueAtTime(0, t); g.gain.linearRampToValueAtTime(vol, t + 0.008); g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(audio.destination); o.start(t); o.stop(t + dur + 0.02);
  }

  // ---------- state ----------
  const queue = [];                // incoming samples {m, s}
  let scratchUntil = 0;            // performance.now() until which samples are "scratch"
  let scratching = false, scratchStartedAt = 0;
  let count = 0, totalSeconds = 0, lastScratchAt = null, currentHz = null;
  const sessionStart = Date.now();
  const strip = [];                // {start, end} in Date.now() ms
  let lastBatchAt = 0, simulate = false;

  function setLive() {
    const live = simulate || Date.now() - lastBatchAt < 3500;
    $("#liveDot").classList.toggle("live", live);
    document.querySelector(".status").classList.toggle("live", live);
    $("#liveText").textContent = simulate ? "SIMULATION" : live ? "WATCH LIVE" : "WAITING FOR WATCH";
    $("#modeText").textContent = simulate ? "SIMULATION" : "LIVE";
  }
  setInterval(setLive, 500);

  function scratchStart(hz, intense) {
    if (scratching) return;
    scratching = true; scratchStartedAt = Date.now();
    count += 1; lastScratchAt = Date.now(); if (hz) currentHz = hz;
    const v = $("#vCount"); v.textContent = count; v.classList.add("bump"); setTimeout(() => v.classList.remove("bump"), 260);
    $("#alarm").classList.add("on"); document.querySelector(".trace-wrap").classList.add("hot");
    strip.push({ start: Date.now(), end: null, intense });
    beep(1318, 0.09, 0.2); beep(1318, 0.09, 0.2, 0.14);
  }
  function scratchEnd(seconds) {
    if (!scratching) return;
    scratching = false;
    const dur = seconds || (Date.now() - scratchStartedAt) / 1000;
    totalSeconds += dur;
    const last = strip[strip.length - 1]; if (last && !last.end) last.end = Date.now();
    $("#alarm").classList.remove("on"); document.querySelector(".trace-wrap").classList.remove("hot");
  }
  // while scratching: a soft monitor beep every 0.6 s
  setInterval(() => { if (scratching) beep(988, 0.07, 0.12); }, 600);

  function reset() {
    count = 0; totalSeconds = 0; lastScratchAt = null; strip.length = 0; currentHz = null;
    $("#vCount").textContent = "0"; scratchEnd(0);
  }

  // vitals text
  setInterval(() => {
    const live = scratching ? (Date.now() - scratchStartedAt) / 1000 : 0;
    const t = Math.round(totalSeconds + live);
    $("#vTime").textContent = `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
    $("#vLast").textContent = lastScratchAt ? (scratching ? "now" : `${Math.round((Date.now() - lastScratchAt) / 1000)} s ago`) : "—";
    $("#vHz").textContent = currentHz ? `${currentHz.toFixed(1)} HZ BACK-AND-FORTH` : "— HZ";
    // strip
    const el = $("#strip"); const span = Math.max(60000, Date.now() - sessionStart);
    el.innerHTML = strip.map((s) => {
      const l = ((s.start - (Date.now() - span)) / span) * 100, w = (((s.end || Date.now()) - s.start) / span) * 100;
      return `<i style="left:${Math.max(0, l)}%;width:${Math.max(0.3, w)}%"></i>`;
    }).join("");
  }, 250);

  // ---------- data in ----------
  function onBatch(msg) {
    lastBatchAt = Date.now();
    for (const s of msg.samples || []) queue.push({ m: +s[1] || 0 });
    for (const w of msg.windows || []) {
      if (w.scratch) { scratchUntil = performance.now() + 3200; if (w.hz) currentHz = w.hz; }
      const mtr = $("#vMeter"); mtr.style.width = Math.min(100, (w.p || 0) * 100) + "%";
    }
    for (const e of msg.events || []) {
      if (e.type === "start") scratchStart(e.hz, e.intense);
      if (e.type === "end") scratchEnd(e.seconds);
    }
    if (queue.length > RATE * 6) queue.splice(0, queue.length - RATE * 2);   // far behind: jump ahead
  }
  window.twinOnBatch = onBatch;

  let ws, retry = 0;
  function connect() {
    const proto = location.protocol === "https:" ? "wss:" : "ws:";
    ws = new WebSocket(`${proto}//${location.host}/api/live`);
    ws.onopen = () => { retry = 0; };
    ws.onmessage = (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "batch" && !simulate) onBatch(msg);
      if (msg.type === "reset") reset();
    };
    ws.onclose = () => { setTimeout(connect, Math.min(5000, 500 * 2 ** retry++)); };
    ws.onerror = () => { try { ws.close(); } catch {} };
  }
  connect();
  setInterval(() => { if (ws && ws.readyState === 1) ws.send("ping"); }, 15000);

  // ---------- simulation (rehearsal without a watch) ----------
  let simT = 0, simNextScratch = 4, simScratchLeft = 0, simTimer = null;
  function simTick() {
    const batch = { samples: [], windows: [], events: [] };
    for (let i = 0; i < RATE / 5; i++) {
      simT += 1 / RATE;
      let m = 0.006 + Math.random() * 0.01;
      if (simScratchLeft > 0) {
        m = 0.16 + 0.22 * Math.abs(Math.sin(simT * 2 * Math.PI * 4.4)) + Math.random() * 0.05;
        simScratchLeft -= 1 / RATE;
        if (simScratchLeft <= 0) batch.events.push({ type: "end", seconds: 5.2 });
      } else if (simT >= simNextScratch) {
        simScratchLeft = 4 + Math.random() * 3; simNextScratch = simT + simScratchLeft + 7 + Math.random() * 6;
        batch.events.push({ type: "start", hz: 4.2 + Math.random(), intense: Math.random() < 0.3 });
      }
      batch.samples.push([simT, m]);
    }
    if (simScratchLeft > 0) batch.windows.push({ p: 0.9, scratch: true, hz: 4.4 });
    else batch.windows.push({ p: 0.05 + Math.random() * 0.1, scratch: false });
    onBatch(batch);
  }
  function setSim(on) {
    simulate = on; clearInterval(simTimer);
    if (on) { simTimer = setInterval(simTick, 200); } else { scratchEnd(0); }
    setLive();
  }

  document.addEventListener("keydown", (e) => {
    if (e.key === "f" || e.key === "F") { document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen(); }
    if (e.key === "d" || e.key === "D") setSim(!simulate);
    if (e.key === "r" || e.key === "R") reset();
    if (["1", "2", "3", "4"].includes(e.key)) show(["monitor", "night", "history", "claude"][+e.key - 1]);
  });
  if (new URLSearchParams(location.search).get("sim") === "1") setSim(true);

  // ---------- trace (hospital-monitor sweep) ----------
  const cv = $("#trace"), ctx = cv.getContext("2d");
  let W = 0, H = 0, dpr = 1, cols = [], cursor = 0, phase = 0, carry = 0, lastFrame = performance.now(), smooth = 0;
  function resize() {
    dpr = window.devicePixelRatio || 1;
    const r = cv.getBoundingClientRect(); W = r.width; H = r.height;
    cv.width = W * dpr; cv.height = H * dpr;
    const n = Math.ceil(W / PX_PER_SAMPLE) + 1;
    if (cols.length !== n) { cols = new Array(n).fill(null); cursor = 0; }
  }
  window.addEventListener("resize", resize); resize();

  function frame(now) {
    const dt = Math.min(0.1, (now - lastFrame) / 1000); lastFrame = now;
    // play out samples at the watch's rate; speed up when the queue grows (network bursts)
    const speed = queue.length > RATE * 2 ? 2.2 : queue.length > RATE ? 1.4 : 1;
    carry += dt * RATE * speed;
    while (carry >= 1) {
      carry -= 1;
      const s = queue.length ? queue.shift() : { m: 0.004 + Math.random() * 0.004 };
      const isScratch = performance.now() < scratchUntil || scratching;
      smooth += (s.m - smooth) * 0.5;
      const g = Math.min(1, Math.pow(Math.max(0, smooth - 0.014) / 0.2, 0.55)); // calm at rest, exaggerate real motion
      const amp = (isScratch ? 1.35 : 0.9) * g * H * 0.36 + H * 0.006;
      phase += isScratch ? 2.1 : 1.2;
      cols[cursor] = { y: Math.sin(phase) * amp * (0.75 + Math.random() * 0.25), s: isScratch };
      cursor = (cursor + 1) % cols.length;
      cols[cursor] = null;                                                   // erase ahead of the pen
      for (let k = 1; k < 8; k++) cols[(cursor + k) % cols.length] = null;
    }
    draw();
    requestAnimationFrame(frame);
  }

  function draw() {
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, W, H);
    const mid = H * 0.55;
    ctx.lineJoin = "round"; ctx.lineCap = "round";
    // two passes: glow, then core
    for (const pass of [0, 1]) {
      ctx.lineWidth = pass ? 2.4 : 8;
      let prev = null;
      for (let i = 0; i < cols.length; i++) {
        const c = cols[i];
        if (!c) { prev = null; continue; }
        const x = i * PX_PER_SAMPLE, y = mid - c.y;
        if (prev) {
          ctx.strokeStyle = c.s ? (pass ? "#f8a16f" : "rgba(248,161,111,.28)") : (pass ? "#a9d877" : "rgba(169,216,119,.18)");
          ctx.beginPath(); ctx.moveTo(prev.x, prev.y); ctx.lineTo(x, y); ctx.stroke();
        }
        prev = { x, y };
      }
    }
    // pen dot
    const pi = (cursor - 1 + cols.length) % cols.length, pc = cols[pi];
    if (pc) {
      ctx.fillStyle = pc.s ? "#f8a16f" : "#d8ffb0";
      ctx.shadowColor = pc.s ? "#f8a16f" : "#a9d877"; ctx.shadowBlur = 18;
      ctx.beginPath(); ctx.arc(pi * PX_PER_SAMPLE, mid - pc.y, 4.5, 0, Math.PI * 2); ctx.fill();
      ctx.shadowBlur = 0;
    }
  }
  requestAnimationFrame(frame);
})();
