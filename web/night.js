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

  // the two neighbouring hours with the most scratching ("2–4 AM")
  function worstPair(hours) {
    let best = 0;
    for (let k = 1; k < hours.length - 1; k++) if (hours[k][1] + hours[k + 1][1] > hours[best][1] + hours[best + 1][1]) best = k;
    return [best, best + 1];
  }
  const hourLabel = (h) => h.replace(/([AP])$/, " $1M");   // "2A" → "2 AM"

  let shown = 0;   // a newer show() wins over a slower earlier one
  async function show() {
    const token = ++shown, bars = $("#nightBars");
    bars.classList.remove("shown"); bars.textContent = ""; $("#nLive").textContent = "";
    ["#nMin", "#nEp", "#nInt"].forEach((id) => { $(id).textContent = "0"; }); $("#nWake").textContent = "0×";
    const live = await liveEpisodes();
    if (token !== shown) return;

    const liveSec = live.reduce((a, e) => a + (e.seconds || 0), 0);
    const minutes = S.NIGHTS[S.NIGHTS.length - 1] + liveSec / 60;
    const last = S.nightDate(S.NIGHTS.length - 1);
    $("#nightRange").textContent = `LAST NIGHT · ${S.wd(last).toUpperCase()} ${S.LAST_NIGHT.from} → ${S.LAST_NIGHT.to}`;
    $("#nMin").style.minWidth = `${String(Math.round(minutes)).length}ch`;   // the headline doesn't shift while counting
    $("#nWorst").textContent = S.LAST_NIGHT.worst;
    $("#nRatio").textContent = `▲ ${(minutes / S.USUAL).toFixed(1)}× his usual`;
    // count up as each card rises in (night.css staggers them the same way)
    const later = (ms, fn) => setTimeout(() => { if (token === shown) fn(); }, ms);
    later(150, () => countUp($("#nMin"), minutes));
    later(220, () => countUp($("#nEp"), S.LAST_NIGHT.episodes + live.length));
    later(290, () => countUp($("#nInt"), S.LAST_NIGHT.intense + live.filter((e) => e.intense).length));
    later(360, () => countUp($("#nWake"), S.LAST_NIGHT.woke, 700, (v) => Math.round(v) + "×"));

    // hour by hour with the worst two hours hot, then a pink NOW bar for what the watch caught
    const top = 12, hours = S.LAST_NIGHT_HOURS, [w0, w1] = worstPair(hours);
    const cols = hours.map(([h, m], k) => ({ h: m / top, cls: k === w0 || k === w1 ? "hot" : "", value: `${m} min`, label: hourLabel(h) }));
    if (liveSec > 0) {
      const s = Math.round(liveSec);
      cols.push({ h: Math.max(0.12, liveSec / 60 / top), cls: "live", value: `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`, label: "NOW" });
    }
    bars.innerHTML = cols.map((c, k) => `<div class="col ${c.cls}" style="--h:${Math.min(1, c.h).toFixed(3)};--i:${k}">`
      + `<div class="plot"><i class="bar"></i><b class="val">${c.value}</b></div><span class="hr">${c.label}</span></div>`).join("");
    requestAnimationFrame(() => requestAnimationFrame(() => bars.classList.add("shown")));
    $("#nLive").textContent = live.length ? `Includes ${live.length} scratch${live.length > 1 ? "es" : ""} the watch caught live just now.` : "";
  }

  window.addEventListener("twin:page", (e) => { if (e.detail === "night") show(); });
})();
