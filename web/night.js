// Last night (#p-night): the bundled night from window.twinStory plus scratches the watch caught live.
(() => {
  const $ = (s) => document.querySelector(s);
  const S = window.twinStory, { countUp } = window.twinUI;

  // This session's scratches, or (after a reload) the ones the relay stored since the last reset.
  async function liveEpisodes() {
    const local = window.twinSession ? window.twinSession() : null;
    if (local && local.episodes.length) return local.episodes;
    const since = Math.max(Date.now() - 12 * 3600 * 1000, +(localStorage.getItem("twinSince") || 0)) / 1000;
    try {
      const j = await (await fetch(window.twinUI.api(`/api/events?since=${since}`))).json();
      return (j.episodes || []).map((e) => ({ seconds: e.seconds, intense: e.intense }));
    } catch { return []; }
  }

  async function show() {
    const live = await liveEpisodes();
    const liveSec = live.reduce((a, e) => a + (e.seconds || 0), 0);
    const minutes = S.NIGHTS[S.NIGHTS.length - 1] + liveSec / 60;
    const last = S.nightDate(S.NIGHTS.length - 1);
    $("#nightRange").textContent = `LAST NIGHT · ${S.wd(last).toUpperCase()} ${S.LAST_NIGHT.from} → ${S.LAST_NIGHT.to}`;
    countUp($("#nMin"), minutes);
    countUp($("#nEp"), S.LAST_NIGHT.episodes + live.length);
    countUp($("#nInt"), S.LAST_NIGHT.intense + live.filter((e) => e.intense).length);
    countUp($("#nWake"), S.LAST_NIGHT.woke, 700, (v) => Math.round(v) + "×");
    $("#nWorst").textContent = S.LAST_NIGHT.worst;
    $("#nRatio").textContent = `▲ ${(minutes / S.USUAL).toFixed(1)}× his usual`;

    const max = 12;
    const bars = S.LAST_NIGHT_HOURS.map(([, m]) => ({ h: m / max, hot: m >= 6, label: `${m}m` }));
    if (liveSec > 0) {
      const s = Math.round(liveSec);
      bars.push({ h: Math.max(0.12, liveSec / 60 / max), live: true, label: `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` });
    }
    const el = $("#nightBars");
    el.classList.remove("shown");
    el.innerHTML = bars.map((b) => `<i class="${b.hot ? "hot" : ""} ${b.live ? "live" : ""}"><b>${b.label}</b></i>`).join("");
    $("#nightAxis").innerHTML = S.LAST_NIGHT_HOURS.map(([h]) => `<span>${h}</span>`).join("") + (liveSec > 0 ? `<span class="mark">NOW</span>` : "");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      [...el.children].forEach((c, k) => { c.style.transitionDelay = `${k * 70}ms`; c.style.height = `${Math.min(100, bars[k].h * 100)}%`; });
      el.classList.add("shown");
    }));
    $("#nLive").textContent = live.length ? `Includes ${live.length} scratch${live.length > 1 ? "es" : ""} the watch caught live just now.` : "";
  }

  window.addEventListener("twin:page", (e) => { if (e.detail === "night") show(); });
})();
