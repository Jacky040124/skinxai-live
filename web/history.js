// History (#p-history): 14 nights against his usual. Shows only that the last nights are higher; no causes.
(() => {
  const $ = (s) => document.querySelector(s);
  const S = window.twinStory, { countUp } = window.twinUI;

  function show() {
    const last3 = S.NIGHTS.slice(-3), avg3 = last3.reduce((a, b) => a + b, 0) / 3;
    countUp($("#hAvg"), avg3);
    $("#hUsual").textContent = S.USUAL;
    $("#hChange").textContent = `▲ ${(avg3 / S.USUAL).toFixed(1)}× his usual, 3 nights running`;
    $("#hTitleLead").textContent = `Since ${S.wd(S.nightDate(S.NIGHTS.length - 3), true)}:`;

    const top = 52;
    const el = $("#histBars");
    el.classList.remove("shown");
    el.innerHTML = S.NIGHTS.map((m) => `<div class="col"><i class="${m > S.USUAL * 1.5 ? "hot" : ""}"><b>${m}</b></i></div>`).join("")
      + `<div class="usual" style="bottom:${(S.USUAL / top) * 100}%"><span>HIS USUAL<br>${S.USUAL} MIN</span></div>`;
    $("#histAxis").innerHTML = S.NIGHTS.map((_, i) => {
      const d = S.nightDate(i);
      return `<span>${S.wd(d).slice(0, 2).toUpperCase()}<br>${d.getDate()}</span>`;
    }).join("");
    requestAnimationFrame(() => requestAnimationFrame(() => {
      el.querySelectorAll(".col i").forEach((b, k) => { b.style.transitionDelay = `${k * 45}ms`; b.style.height = `${(S.NIGHTS[k] / top) * 100}%`; });
      el.classList.add("shown");
    }));
  }

  window.addEventListener("twin:page", (e) => { if (e.detail === "history") show(); });
})();
