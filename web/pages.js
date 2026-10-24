// Eczema Twin · story pages: Last night, History, Claude.
// Douglas's last 14 nights are a bundled story; scratches the watch catches live are added on top.
// Keys: A (or the button) asks Claude · L asks the live model instead of the bundled answer.
(() => {
  const $ = (s) => document.querySelector(s);
  const DAY = 86400000;
  const params = new URLSearchParams(location.search);

  // ---------- the story ----------
  const USUAL = 12;                                                        // minutes a night, his usual
  const NIGHTS = [11, 13, 10, 12, 14, 11, 12, 13, 12, 13, 15, 22, 31, 41]; // oldest → last night
  const SLEEP = [7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1];
  const HUMIDITY = [52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29];
  const SHAMPOO = 10, DRY = 13, EXAMS = [1, 3];                            // night indexes
  const LAST_NIGHT_HOURS = [["11P", 1], ["12A", 3], ["1A", 6], ["2A", 10], ["3A", 11], ["4A", 6], ["5A", 3], ["6A", 1]];
  const LAST_NIGHT = { episodes: 23, intense: 7, woke: 4, worst: "2–4 AM", from: "11:04 PM", to: "6:52 AM" };

  // night i started on the evening of this date (last night = yesterday)
  const nightDate = (i) => { const d = new Date(); d.setHours(12, 0, 0, 0); return new Date(d - (NIGHTS.length - i) * DAY); };
  const wd = (d, long) => d.toLocaleDateString("en-US", { weekday: long ? "long" : "short" });
  const md = (d) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const day = (i, long) => wd(nightDate(i), long);

  // ---------- small animation helpers ----------
  const ease = (t) => 1 - Math.pow(1 - t, 3);
  function countUp(el, to, ms = 900, fmt = (v) => Math.round(v)) {
    const t0 = performance.now();
    const step = (now) => {
      const t = Math.min(1, (now - t0) / ms);
      el.textContent = fmt(to * ease(t));
      if (t < 1) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
  const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));

  // ---------- live scratches (this session, or stored by the relay if the page reloaded) ----------
  async function liveEpisodes() {
    const local = window.twinSession ? window.twinSession() : null;
    if (local && local.episodes.length) return local.episodes;
    const since = Math.max(Date.now() - 12 * 3600 * 1000, +(localStorage.getItem("twinSince") || 0)) / 1000;
    try {
      const r = await fetch(`/api/events?since=${since}`);
      const j = await r.json();
      return (j.episodes || []).map((e) => ({ seconds: e.seconds, intense: e.intense }));
    } catch { return []; }
  }

  // ---------- LAST NIGHT ----------
  async function showNight() {
    const live = await liveEpisodes();
    const liveSec = live.reduce((a, e) => a + (e.seconds || 0), 0);
    const minutes = NIGHTS[NIGHTS.length - 1] + liveSec / 60;
    const last = nightDate(NIGHTS.length - 1);
    $("#nightRange").textContent = `LAST NIGHT · ${wd(last).toUpperCase()} ${LAST_NIGHT.from} → ${LAST_NIGHT.to}`;
    countUp($("#nMin"), minutes);
    countUp($("#nEp"), LAST_NIGHT.episodes + live.length);
    countUp($("#nInt"), LAST_NIGHT.intense + live.filter((e) => e.intense).length);
    countUp($("#nWake"), LAST_NIGHT.woke, 700, (v) => Math.round(v) + "×");
    $("#nWorst").textContent = LAST_NIGHT.worst;
    $("#nRatio").textContent = `▲ ${(minutes / USUAL).toFixed(1)}× his usual`;

    const hours = LAST_NIGHT_HOURS.slice();
    const max = 12;
    const bars = hours.map(([, m]) => ({ v: m, h: m / max, hot: m >= 6, label: `${m}m` }));
    if (liveSec > 0) {
      const s = Math.round(liveSec);
      bars.push({ v: liveSec / 60, h: Math.max(0.12, liveSec / 60 / max), live: true, label: `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` });
    }
    const el = $("#nightBars");
    el.classList.remove("shown");
    el.innerHTML = bars.map((b) => `<i class="${b.hot ? "hot" : ""} ${b.live ? "live" : ""}"><b>${b.label}</b></i>`).join("");
    $("#nightAxis").innerHTML = hours.map(([h]) => `<span>${h}</span>`).join("") + (liveSec > 0 ? `<span class="mark">NOW</span>` : "");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      [...el.children].forEach((c, k) => { c.style.transitionDelay = `${k * 70}ms`; c.style.height = `${Math.min(100, bars[k].h * 100)}%`; });
      el.classList.add("shown");
    }));
    $("#nLive").textContent = live.length
      ? `Includes ${live.length} scratch${live.length > 1 ? "es" : ""} the watch caught live just now.`
      : "";
  }

  // ---------- HISTORY ----------
  function showHistory() {
    const last3 = NIGHTS.slice(-3), avg3 = last3.reduce((a, b) => a + b, 0) / 3;
    countUp($("#hAvg"), avg3);
    $("#hUsual").textContent = USUAL;
    $("#hChange").textContent = `▲ ${(avg3 / USUAL).toFixed(1)}× his usual, 3 nights running`;
    $("#hTitleLead").textContent = `Since ${day(NIGHTS.length - 3, true)}:`;

    const top = 52;
    const flags = { [SHAMPOO]: ["NEW SHAMPOO", "pink"], [DRY]: ["DRY AIR", "cyan"], [EXAMS[0]]: ["MIDTERMS", "yellow"] };
    const el = $("#histBars");
    el.classList.remove("shown");
    el.innerHTML = NIGHTS.map((m, i) => {
      const f = flags[i];
      const exam = i >= EXAMS[0] && i <= EXAMS[1];
      return `<div class="col${exam ? " exam" : ""}">${f ? `<span class="flag ${f[1]}">${f[0]}</span>` : ""}<i class="${m > USUAL * 1.5 ? "hot" : ""}"><b>${m}</b></i></div>`;
    }).join("") + `<div class="usual" style="bottom:${(USUAL / top) * 100}%"><span>HIS USUAL<br>${USUAL} MIN</span></div>`;
    $("#histAxis").innerHTML = NIGHTS.map((_, i) => {
      const d = nightDate(i);
      return `<span class="${i === SHAMPOO ? "mark" : ""}">${wd(d).slice(0, 2).toUpperCase()}<br>${d.getDate()}</span>`;
    }).join("");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      el.querySelectorAll(".col i").forEach((b, k) => { b.style.transitionDelay = `${k * 45}ms`; b.style.height = `${(NIGHTS[k] / top) * 100}%`; });
      el.classList.add("shown");
    }));

    $("#changes").innerHTML = [
      ["PRODUCT", "pink", `New shampoo · ${day(SHAMPOO)} ${md(nightDate(SHAMPOO))}`, "first time · photo of the label"],
      ["WEATHER", "cyan", `Dry air, ${HUMIDITY[DRY]}% · ${day(DRY)}`, "automatic · local weather"],
      ["CALENDAR", "yellow", `Midterms · ${md(nightDate(EXAMS[0]))}–${nightDate(EXAMS[1]).getDate()}`, "automatic · calendar"],
      ["SLEEP", "lime", `${SLEEP[SLEEP.length - 1]} h sleep · last night`, "automatic · Apple Watch"],
    ].map(([t, c, what, how]) => `<div><span class="t ${c}">${t}</span><span><b>${what}</b><small>${how}</small></span></div>`).join("");
  }

  // ---------- CLAUDE ----------
  function bundledCase() {
    const s = day(SHAMPOO, true), next = day(SHAMPOO + 1, true), dry = day(DRY, true);
    return {
      source: "Bundled analysis",
      summary: `Your scratching started climbing the night after you first used a new shampoo on ${s}, and it has gotten worse every night since: ${NIGHTS[SHAMPOO + 1]}, ${NIGHTS[SHAMPOO + 2]}, then ${NIGHTS[SHAMPOO + 3]} minutes. That one-to-three-day delay is typical of a skin reaction to something new. Nothing else changed at the right time.`,
      suspects: [
        { title: "Your new shampoo", confidence: "high", lag: `STARTED ${s.toUpperCase()} · +1 DAY · WORSE EVERY NIGHT`,
          evidence: `It isn't in any of your earlier logs. Scratching rose on ${next} night and kept climbing. The label lists fragrance and methylisothiazolinone, two common causes of contact eczema.` },
        { title: "Dry air", confidence: "low", lag: `ONLY LAST NIGHT · TOO LATE`,
          evidence: `Humidity fell to ${HUMIDITY[DRY]}% on ${dry}, two nights after the rise began. It may be making things worse, but it didn't start it.` },
        { title: "Stress", confidence: "low", lag: "MIDTERMS · NO EFFECT",
          evidence: `Your stress was higher during midterms (${md(nightDate(EXAMS[0]))}–${nightDate(EXAMS[1]).getDate()}) and your scratching stayed at its usual ${USUAL} minutes.` },
      ],
      nextStep: `Go back to your old shampoo for 5 nights. If your scratching falls back toward ${USUAL} minutes a night, you've found your trigger. Bring the label to your dermatologist and ask about a patch test.`,
    };
  }

  function storyLog() {
    return {
      person: "Douglas, 21, eczema since childhood. Apple Watch measures scratching during sleep.",
      usualMinutesPerNight: USUAL,
      nights: NIGHTS.map((m, i) => ({
        date: nightDate(i).toISOString().slice(0, 10), weekday: day(i, true), scratchMinutes: m, sleepHours: SLEEP[i], humidityPercent: HUMIDITY[i],
        events: [i === SHAMPOO ? "started a new shampoo (first time ever; label lists fragrance, methylisothiazolinone)" : null,
          i >= EXAMS[0] && i <= EXAMS[1] ? "midterm exams (stress high)" : null].filter(Boolean),
      })),
      unchanged: ["laundry detergent (same for months)", "moisturizer", "diet", "bedding washed weekly"],
      question: "Why is my eczema so bad today?",
    };
  }

  async function liveCase(model) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), 22000);
    try {
      const r = await fetch("/api/analyze", { method: "POST", signal: ctl.signal, headers: { "content-type": "application/json" }, body: JSON.stringify({ model, log: storyLog() }) });
      const j = await r.json();
      if (!j.caseFile || !j.caseFile.summary) return null;
      const c = j.caseFile;
      return {
        source: `${j.model} · live`,
        summary: c.summary,
        suspects: (c.suspects || []).slice(0, 3).map((s) => ({ title: s.title, confidence: String(s.confidence || "low").toLowerCase(), lag: String(s.lag || "").toUpperCase(), evidence: s.evidence })),
        nextStep: c.nextStep,
      };
    } catch { return null; } finally { clearTimeout(timer); }
  }

  let asking = false;
  async function ask(live) {
    if (asking) return;
    asking = true;
    const btn = $("#askBtn"); btn.disabled = true; btn.textContent = "✶ Thinking…";
    ["#summaryCard", "#nextCard", "#disc"].forEach((s) => $(s).classList.remove("on"));
    $("#suspects").innerHTML = ""; $("#summary").textContent = "";
    const think = $("#thinking"); think.classList.add("on");
    const lines = ["Reading 14 nights of scratching, sleep and weather…", "Lining up everything that changed…", "Checking the 1–3 day delays…", "Ruling things out…"];
    let k = 0; $("#thinkText").textContent = lines[0];
    const lineTimer = setInterval(() => { k = (k + 1) % lines.length; $("#thinkText").textContent = lines[k]; }, 1100);
    const order = [0, 1, 2, 5, 8, 7, 6, 3, 4];
    const cells = [...$("#pix").children]; let p = 0;
    const pixTimer = setInterval(() => { cells.forEach((c, i) => c.classList.toggle("lit", order.indexOf(i) <= p % 9 && order.indexOf(i) > p % 9 - 4)); p++; }, 110);

    const model = params.get("model") || (live ? "anthropic/claude-sonnet-5.5" : null);
    const [result] = await Promise.all([model ? liveCase(model) : Promise.resolve(null), sleepMs(3400)]);
    const c = result || bundledCase();
    clearInterval(lineTimer); clearInterval(pixTimer); think.classList.remove("on");

    $("#srcTag").textContent = `· ${c.source}`;
    $("#summaryCard").classList.add("on");
    await typeOut($("#summary"), c.summary);
    const conf = { high: [0.88, "HIGH"], medium: [0.55, "MEDIUM"], low: [0.16, "LOW"] };
    $("#suspects").innerHTML = c.suspects.map((s, i) => {
      const [w, label] = conf[s.confidence] || conf.low;
      return `<div class="sus${i === 0 ? " top" : ""}" data-w="${w}"><div class="h"><span class="rank">${i + 1}</span><span class="title">${esc(s.title)}</span><span class="conf">${label}</span></div>
        <div class="cbar"><i></i></div><p>${esc(s.evidence || "")}</p><div class="lag">${esc(s.lag || "")}</div></div>`;
    }).join("");
    [...$("#suspects").children].forEach((el, i) => setTimeout(() => {
      el.classList.add("in");
      setTimeout(() => { el.querySelector(".cbar i").style.width = `${+el.dataset.w * 100}%`; }, 250);
    }, i * 260));
    await sleepMs(c.suspects.length * 260 + 600);
    $("#nextText").textContent = c.nextStep || "";
    $("#nextCard").classList.add("on"); $("#disc").classList.add("on");
    btn.disabled = false; btn.textContent = "✶ Ask again"; asking = false;
  }

  function typeOut(el, text) {
    return new Promise((done) => {
      let n = 0;
      const caret = document.createElement("span"); caret.className = "caret";
      const step = () => {
        n = Math.min(text.length, n + 3);
        el.textContent = text.slice(0, n); el.appendChild(caret);
        if (n < text.length) setTimeout(step, 22); else { setTimeout(() => caret.remove(), 600); done(); }
      };
      step();
    });
  }
  const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));

  $("#pix").innerHTML = "<i></i>".repeat(9);
  $("#askBtn").addEventListener("click", () => ask(params.get("live") === "1"));
  document.addEventListener("keydown", (e) => {
    if (!$("#p-claude").classList.contains("on")) return;
    if (e.key === "a" || e.key === "A" || e.key === "Enter") ask(params.get("live") === "1");
    if (e.key === "l" || e.key === "L") ask(true);
  });

  window.addEventListener("twin:page", (e) => {
    if (e.detail === "night") showNight();
    if (e.detail === "history") showHistory();
  });
})();
