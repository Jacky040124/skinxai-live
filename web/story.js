// Douglas's last 14 nights and everything Claude's tools can read. Shared by Last night, History and Claude.
// Night i started on the evening of nightDate(i); night 13 is last night. The trigger in this story is a
// body wash he ordered for the first time the day before night 10 and started using that evening.
(() => {
  const DAY = 86400000;
  const USUAL = 12;                                                        // minutes a night, his usual
  const NIGHTS = [11, 13, 10, 12, 14, 11, 12, 13, 12, 13, 15, 22, 31, 41]; // minutes of scratching, oldest → last night
  const EPISODES = [9, 10, 8, 9, 11, 9, 10, 10, 9, 10, 11, 15, 19, 23];
  const SLEEP = [7.4, 7.1, 6.2, 6.0, 6.4, 7.5, 7.3, 7.2, 7.6, 7.0, 6.9, 6.4, 5.6, 5.1];
  const WAKES = [0, 1, 1, 1, 0, 0, 1, 0, 0, 1, 1, 2, 3, 4];
  const HUMIDITY = [52, 49, 55, 51, 47, 50, 53, 48, 51, 50, 49, 47, 46, 29];
  const TEMP_F = [64, 66, 63, 61, 65, 67, 66, 64, 63, 65, 66, 64, 63, 68];
  const BODY_WASH = 10, DRY = 13, EXAMS = [1, 3];
  const LAST_NIGHT_HOURS = [["11P", 1], ["12A", 3], ["1A", 6], ["2A", 10], ["3A", 11], ["4A", 6], ["5A", 3], ["6A", 1]];
  const LAST_NIGHT = { episodes: 23, intense: 7, woke: 4, worst: "2–4 AM", from: "11:04 PM", to: "6:52 AM" };

  const nightDate = (i) => { const d = new Date(); d.setHours(12, 0, 0, 0); return new Date(d - (NIGHTS.length - i) * DAY); };
  const dayOffset = (i, delta) => new Date(nightDate(i).getTime() + delta * DAY);
  const iso = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  const wd = (d, long) => d.toLocaleDateString("en-US", { weekday: long ? "long" : "short" });
  const md = (d) => d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const today = () => new Date().toLocaleDateString("en-US", { weekday: "long", month: "long", day: "numeric", year: "numeric" });

  // ---- orders: repeat purchases, plus one personal-care item he has never bought before ----
  const BODY_WASH_INGREDIENTS = ["Water", "Sodium Laureth Sulfate", "Cocamidopropyl Betaine", "Fragrance (Parfum)", "Glycerin",
    "Sodium Chloride", "Methylisothiazolinone", "Citric Acid"];
  function orders() {
    const o = (i, delta, item, category, extra) => ({ date: iso(dayOffset(i, delta)), item, category, ...extra });
    return [
      o(0, -60, "Laundry detergent, fragrance-free, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(0, -52, "Coffee beans, 2 lb", "grocery", { bought_before: true }),
      o(0, -45, "Ceramide moisturizing cream, fragrance-free", "personal care", { bought_before: true, note: "repeat purchase, uses daily" }),
      o(0, -40, "Spiral notebooks, 5 pack", "school", { bought_before: true }),
      o(0, -33, "Toothpaste, 2 pack", "personal care", { bought_before: true }),
      o(0, -30, "Laundry detergent, fragrance-free, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(0, -24, "USB-C charging cable", "electronics", { bought_before: false }),
      o(0, -20, "Protein bars, 12 count", "grocery", { bought_before: true }),
      o(0, -15, "Unscented hand soap refill", "household", { bought_before: true }),
      o(0, -8, "Graphing calculator batteries", "school", { bought_before: true }),
      o(2, 0, "Coffee beans, 2 lb", "grocery", { bought_before: true }),
      o(3, 0, "Laundry detergent, fragrance-free, 92 loads", "household", { bought_before: true, note: "same product every month for 2 years" }),
      o(5, 0, "Wool socks, 3 pairs", "clothing", { bought_before: false, note: "washed before wearing" }),
      o(7, 0, "Instant ramen, 24 pack", "grocery", { bought_before: true }),
      o(BODY_WASH, -1, "Body wash, 18 fl oz", "personal care", { bought_before: false, note: "first time ordering any body wash; delivered next day",
        ingredients: BODY_WASH_INGREDIENTS }),
      o(11, 0, "Desk lamp bulb", "household", { bought_before: true }),
      o(12, 0, "Protein bars, 12 count", "grocery", { bought_before: true }),
    ];
  }

  // ---- the tools Claude can call (the page runs them; results go back to the model as JSON) ----
  const clampN = (n, max) => Math.max(1, Math.min(max, Math.round(+n || max)));
  const tools = {
    scratch_history({ nights } = {}) {
      const n = clampN(nights, 14), from = NIGHTS.length - n;
      return {
        usual_minutes_per_night: USUAL, measured_by: "Apple Watch, every night",
        nights: NIGHTS.slice(from).map((m, k) => ({ night_of: iso(nightDate(from + k)), weekday: wd(nightDate(from + k), true),
          scratch_minutes: m, scratch_episodes: EPISODES[from + k] })),
        last_night_worst_hours: LAST_NIGHT.worst,
      };
    },
    order_history({ days } = {}) {
      const since = Date.now() - clampN(days, 120) * DAY;
      return { source: "Amazon order history", orders: orders().filter((x) => new Date(x.date).getTime() >= since) };
    },
    weather_history({ days } = {}) {
      const n = clampN(days, 14), from = NIGHTS.length - n;
      return { location: "Berkeley, CA", days: HUMIDITY.slice(from).map((h, k) => ({ date: iso(nightDate(from + k)), humidity_percent: h, high_f: TEMP_F[from + k] })) };
    },
    calendar_events({ days } = {}) {
      return { events: [
        { date: `${iso(nightDate(EXAMS[0]))} to ${iso(nightDate(EXAMS[1]))}`, title: "Midterm exams (CS 61B, Math 54)", note: "stressful week" },
        { date: iso(nightDate(6)), title: "Dentist" },
        { date: iso(nightDate(9)), title: "Team project deadline" },
        { date: iso(new Date(Date.now() + DAY)), title: "CalHacks 13.0 (hackathon)" },
      ] };
    },
    sleep_history({ nights } = {}) {
      const n = clampN(nights, 14), from = NIGHTS.length - n;
      return { source: "Apple Health", nights: SLEEP.slice(from).map((h, k) => ({ night_of: iso(nightDate(from + k)), hours_asleep: h, wake_ups: WAKES[from + k] })) };
    },
  };

  window.twinStory = { USUAL, NIGHTS, EPISODES, SLEEP, WAKES, HUMIDITY, TEMP_F, BODY_WASH, DRY, EXAMS, LAST_NIGHT_HOURS, LAST_NIGHT,
    BODY_WASH_INGREDIENTS, nightDate, dayOffset, iso, wd, md, today, orders, tools };
})();
