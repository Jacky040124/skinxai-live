// Eczema Twin live relay: Apple Watch -> this Worker -> big-screen web page.
//   POST /api/ingest   (watch, Bearer INGEST_KEY)  {samples:[[t,m]...], windows:[...], events:[...]}
//   GET  /api/live     WebSocket for the web page (live batches + status)
//   GET  /api/events   recent scratch episodes (for "last night")
//   POST /api/reset    (Bearer INGEST_KEY) clear stored episodes
//   POST /api/analyze  ask the model (OpenRouter) about the story + live episodes; bundled fallback on the page
import { DurableObject } from "cloudflare:workers";

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", "access-control-allow-origin": "*" } });

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: { "access-control-allow-origin": "*", "access-control-allow-headers": "authorization,content-type", "access-control-allow-methods": "GET,POST,OPTIONS" } });
    }
    const room = env.ROOM.get(env.ROOM.idFromName("live-v2"));
    if (url.pathname === "/api/ingest" || url.pathname === "/api/reset") {
      const auth = request.headers.get("authorization") || "";
      if (!env.INGEST_KEY || auth !== `Bearer ${env.INGEST_KEY}`) return json({ error: "unauthorized" }, 401);
      return room.fetch(request);
    }
    if (["/api/live", "/api/events", "/api/status", "/api/label", "/api/recording", "/api/recordings"].includes(url.pathname)) return room.fetch(request);
    if (url.pathname === "/api/analyze" && request.method === "POST") return analyze(request, env);
    if (url.pathname === "/api/chat" && request.method === "POST") return chat(request, env);
    return env.ASSETS.fetch(request);
  },
};

export class LiveRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS episodes (id TEXT PRIMARY KEY, start REAL, end REAL, seconds REAL, intense INTEGER, hz REAL, received REAL)`);
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS rec_labels (rec_id TEXT, t REAL, action TEXT, label TEXT, phase TEXT)`);
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS rec_batches (rec_id TEXT, received REAL, body TEXT)`);
      this.lastSeen = (await this.ctx.storage.get("lastSeen")) || null;
      this.rec = (await this.ctx.storage.get("rec")) || null;
    });
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/api/live") {
      if (request.headers.get("Upgrade") !== "websocket") return json({ error: "expected websocket" }, 426);
      const pair = new WebSocketPair();
      this.ctx.acceptWebSocket(pair[1]);
      pair[1].send(JSON.stringify({ type: "hello", lastSeen: this.lastSeen, now: Date.now() / 1000 }));
      return new Response(null, { status: 101, webSocket: pair[0] });
    }
    if (url.pathname === "/api/ingest" && request.method === "POST") {
      let body;
      try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
      const now = Date.now() / 1000;
      this.lastSeen = now;
      this.ctx.storage.put("lastSeen", now);
      const events = Array.isArray(body.events) ? body.events.slice(0, 200) : [];
      for (const e of events) {
        if (e && e.type === "end" && e.id) {
          this.ctx.storage.sql.exec(`INSERT OR REPLACE INTO episodes (id,start,end,seconds,intense,hz,received) VALUES (?,?,?,?,?,?,?)`,
            String(e.id), +e.t || now, +e.end || now, +e.seconds || 0, e.intense ? 1 : 0, +e.hz || 0, now);
        }
      }
      const batch = {
        type: "batch", receivedAt: now, sentAt: body.sentAt || null, live: !!body.live,
        backing: String(body.backing || "").slice(0, 20), appState: String(body.appState || "").slice(0, 12),
        samples: Array.isArray(body.samples) ? body.samples.slice(0, 2000) : [],
        raw: Array.isArray(body.raw) ? body.raw.slice(0, 4000) : [],
        windows: Array.isArray(body.windows) ? body.windows.slice(0, 100) : [],
        events,
      };
      // A labelled test recording is running: keep everything the watch sends (it ends itself after 15 min).
      if (this.rec && now - this.rec.start < 900) {
        this.ctx.storage.sql.exec(`INSERT INTO rec_batches (rec_id, received, body) VALUES (?,?,?)`, this.rec.id, now,
          JSON.stringify({ raw: batch.raw, windows: batch.windows, events: batch.events, sentAt: batch.sentAt }));
      }
      const msg = JSON.stringify(batch);
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true, clients: this.ctx.getWebSockets().length });
    }
    if (url.pathname === "/api/events") {
      const since = +(url.searchParams.get("since") || 0);
      const rows = this.ctx.storage.sql.exec(`SELECT id,start,end,seconds,intense,hz FROM episodes WHERE start >= ? ORDER BY start`, since).toArray();
      return json({ episodes: rows.map(r => ({ ...r, intense: !!r.intense })), lastSeen: this.lastSeen });
    }
    if (url.pathname === "/api/status") return json({ lastSeen: this.lastSeen, clients: this.ctx.getWebSockets().length, now: Date.now() / 1000, recording: this.rec });
    if (url.pathname === "/api/label" && request.method === "POST") {
      let b = {};
      try { b = await request.json(); } catch {}
      const now = Date.now() / 1000;
      const action = String(b.action || "step").slice(0, 16), label = String(b.label || "").slice(0, 80), phase = String(b.phase || "").slice(0, 16);
      if (action === "start") {
        this.rec = { id: new Date().toISOString().replace(/[:.]/g, "-"), start: now, name: String(b.name || "test").slice(0, 60) };
        await this.ctx.storage.put("rec", this.rec);
      }
      if (!this.rec) return json({ error: "no recording" }, 409);
      const id = this.rec.id;
      this.ctx.storage.sql.exec(`INSERT INTO rec_labels (rec_id, t, action, label, phase) VALUES (?,?,?,?,?)`, id, now, action, label, phase);
      if (action === "end") { this.rec = null; await this.ctx.storage.delete("rec"); }
      const msg = JSON.stringify({ type: "label", id, t: now, action, label, phase });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true, id });
    }
    if (url.pathname === "/api/recordings") {
      const rows = this.ctx.storage.sql.exec(`SELECT rec_id, MIN(t) AS start, MAX(t) AS end, COUNT(*) AS labels FROM rec_labels GROUP BY rec_id ORDER BY start DESC LIMIT 20`).toArray();
      return json({ recordings: rows });
    }
    if (url.pathname === "/api/recording") {
      const id = url.searchParams.get("id") || "";
      const labels = this.ctx.storage.sql.exec(`SELECT t, action, label, phase FROM rec_labels WHERE rec_id = ? ORDER BY t`, id).toArray();
      const batches = this.ctx.storage.sql.exec(`SELECT received, body FROM rec_batches WHERE rec_id = ? ORDER BY received`, id).toArray()
        .map((r) => ({ received: r.received, ...JSON.parse(r.body) }));
      return json({ id, labels, batches });
    }
    if (url.pathname === "/api/reset" && request.method === "POST") {
      this.ctx.storage.sql.exec(`DELETE FROM episodes`);
      const msg = JSON.stringify({ type: "reset" });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true });
    }
    return json({ error: "not found" }, 404);
  }

  async webSocketMessage(ws, message) {
    if (message === "ping") ws.send(JSON.stringify({ type: "pong", lastSeen: this.lastSeen, now: Date.now() / 1000 }));
  }
  async webSocketClose(ws, code) { try { ws.close(code, "bye"); } catch {} }
}

async function analyze(request, env) {
  if (!env.OPENROUTER_KEY) return json({ error: "no key" }, 503);
  let body = {};
  try { body = await request.json(); } catch {}
  const model = body.model || env.ANALYSIS_MODEL || "anthropic/claude-sonnet-5.5";
  const system = `You are the trigger-finding assistant inside Eczema Twin. You get a nightly log for one person: minutes of scratching during sleep measured by their Apple Watch, sleep, humidity, and anything that changed. Find their most likely personal flare trigger. Consider 1-3 day delays, check whether each change came before or after the rise began, and rule things out when the timing does not fit. Sleep loss during a flare is usually a result of scratching, not a cause. Use confidence low/medium/high honestly; never diagnose. Talk to the person directly ("you"). Reply with JSON only, no prose around it: {"summary": "2-3 plain sentences", "suspects": [{"title": "at most 4 words", "confidence": "low|medium|high", "lag": "at most 6 words", "evidence": "at most 2 short sentences"}] (2-3 suspects, most likely first), "nextStep": "one or two sentences: a simple test to confirm"}`;
  const ask = async () => {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 25000);
    try {
      const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST", signal: controller.signal,
        headers: { authorization: `Bearer ${env.OPENROUTER_KEY}`, "content-type": "application/json" },
        body: JSON.stringify({ model, max_tokens: 1500, temperature: 0.3, messages: [{ role: "system", content: system }, { role: "user", content: JSON.stringify(body.log || {}) }] }),
      });
      const j = await r.json();
      const text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
      const a = text.indexOf("{"), b = text.lastIndexOf("}");
      if (a < 0 || b <= a) throw new Error(`no json (${r.status}) ${text.slice(0, 80)}`);
      return JSON.parse(text.slice(a, b + 1));
    } finally { clearTimeout(timer); }
  };
  let last;
  for (let attempt = 0; attempt < 2; attempt++) {
    try { return json({ model, caseFile: await ask() }); } catch (e) { last = e; if (String(e).includes("abort")) break; }
  }
  return json({ error: "analysis failed", detail: String(last).slice(0, 160) }, 502);
}

// ---------- Claude chat (the "Claude" page): real model, our tools, steered by instructions ----------
// The page runs the tools itself (the data lives in web/story.js) and sends the conversation back;
// this endpoint only adds the instructions and tool list and asks the model for its next turn.
const CHAT_MODELS = ["anthropic/claude-sonnet-5.5", "anthropic/claude-opus-5.5", "anthropic/claude-haiku-5.5", "deepseek/deepseek-v4.1-flash"];

const CHAT_SYSTEM = (today) => `You are Claude, connected to Eczema Twin: an app that measures how much a person scratches in their sleep with their Apple Watch. You are talking with Douglas, a 21-year-old student with eczema, inside the Eczema Twin app. Today is ${today}.

Style: warm, calm, plain English. Short turns: 1-3 sentences. No markdown headings, no long lists. Never give a diagnosis; you look for patterns in his data.
Every reply starts with one or two short sentences of text before any tool call. Until you have called show_conclusion, every reply must also call a tool: if you say you will check or ask something, do it with a tool call in that same reply.

When he asks why his eczema is bad, work like this:
1. Gather data first. Call scratch_history, order_history, weather_history, calendar_events and sleep_history (several in one turn is fine). Don't ask him for things a tool can tell you.
2. Look for what changed one to three days before his scratching started rising. Things that touch the skin every day (soaps, body wash, shampoo, lotion, detergent) are the prime suspects; something bought for the first time is more suspicious than a repeat purchase.
3. Call show_timeline to mark the most suspicious change on his scratching chart, and show_product for that product (no brand names; describe it generically, e.g. "Body wash").
4. Then rule out the other explanations before concluding. Ask exactly three short questions, ONE per turn (never call ask_user twice in the same turn), each with ask_user and 2-3 short answer options: whether he changed his laundry detergent, whether this week has been more stressful than usual, and where the itch is worst. When Douglas answers, first say in one sentence what the answer rules in or out, using his data (e.g. stress was higher during midterms and his scratching didn't change), then ask the next question in the same reply.
5. Finally call show_conclusion with the most likely cause, your confidence, what you ruled out and why, and a simple test: go back to the old product for 5 nights while the watch keeps measuring. Close with one short sentence.
Only use facts returned by the tools. If an answer points somewhere else, take it seriously and say what would distinguish the two.`;

const CHAT_TOOLS = [
  { name: "scratch_history", description: "Minutes of scratching measured by the Apple Watch for each of the last nights, plus his usual level.", parameters: { type: "object", properties: { nights: { type: "integer", description: "How many nights, up to 14" } }, required: ["nights"] } },
  { name: "order_history", description: "His online orders (Amazon) with item, category and whether he bought it before.", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "weather_history", description: "Daily outdoor humidity and temperature where he lives.", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "calendar_events", description: "Events from his calendar (exams, travel, deadlines).", parameters: { type: "object", properties: { days: { type: "integer" } }, required: ["days"] } },
  { name: "sleep_history", description: "Hours of sleep and wake-ups per night from Apple Health.", parameters: { type: "object", properties: { nights: { type: "integer" } }, required: ["nights"] } },
  { name: "show_timeline", description: "Show his nightly scratching chart as a card in the conversation, with one change marked on it.", parameters: { type: "object", properties: { marker_date: { type: "string", description: "YYYY-MM-DD of the change" }, marker_label: { type: "string", description: "Short label, e.g. 'Started new body wash'" }, note: { type: "string", description: "One short sentence about the timing" } }, required: ["marker_date", "marker_label"] } },
  { name: "show_product", description: "Show the suspected product as a card in the conversation.", parameters: { type: "object", properties: { name: { type: "string", description: "Generic name, no brand" }, purchase_date: { type: "string" }, flagged_ingredients: { type: "array", items: { type: "string" } }, note: { type: "string" } }, required: ["name", "purchase_date"] } },
  { name: "ask_user", description: "Ask Douglas one short question with 2-3 answer buttons. The result is his answer.", parameters: { type: "object", properties: { question: { type: "string" }, options: { type: "array", items: { type: "string" }, minItems: 2, maxItems: 3 } }, required: ["question", "options"] } },
  { name: "show_conclusion", description: "Show the conclusion as a card in the conversation.", parameters: { type: "object", properties: { cause: { type: "string", description: "The most likely cause in at most 8 words, e.g. 'The new body wash'" }, confidence: { type: "string", enum: ["low", "medium", "high"] }, ruled_out: { type: "array", items: { type: "object", properties: { item: { type: "string" }, reason: { type: "string" } }, required: ["item", "reason"] } }, next_step: { type: "string" } }, required: ["cause", "confidence", "next_step"] } },
].map((f) => ({ type: "function", function: f }));

async function chat(request, env) {
  if (!env.OPENROUTER_KEY) return json({ error: "no key" }, 503);
  let body = {};
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const model = CHAT_MODELS.includes(body.model) ? body.model : CHAT_MODELS[0];
  const today = /^[A-Za-z]+, [A-Za-z]+ \d{1,2}, \d{4}$/.test(body.today || "") ? body.today : new Date().toDateString();
  const raw = Array.isArray(body.messages) ? body.messages.slice(-80) : [];
  let size = 0;
  const messages = [];
  for (const m of raw) {
    if (!m || !["user", "assistant", "tool"].includes(m.role)) continue;
    const content = typeof m.content === "string" ? m.content.slice(0, 12000) : "";
    size += content.length;
    const out = { role: m.role, content };
    if (m.role === "assistant" && Array.isArray(m.tool_calls)) {
      out.tool_calls = m.tool_calls.slice(0, 8).map((c) => ({ id: String(c.id).slice(0, 80), type: "function",
        function: { name: String(c.function && c.function.name).slice(0, 40), arguments: String(c.function && c.function.arguments || "{}").slice(0, 4000) } }));
    }
    if (m.role === "tool") out.tool_call_id = String(m.tool_call_id || "").slice(0, 80);
    messages.push(out);
  }
  if (!messages.length || size > 80000) return json({ error: "bad conversation" }, 400);
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 40000);
  try {
    const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST", signal: controller.signal,
      headers: { authorization: `Bearer ${env.OPENROUTER_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ model, temperature: 0.3, max_tokens: 1200, tools: CHAT_TOOLS, tool_choice: "auto",
        messages: [{ role: "system", content: CHAT_SYSTEM(today) }, ...messages] }),
    });
    const j = await r.json();
    const msg = j.choices && j.choices[0] && j.choices[0].message;
    if (!msg) return json({ error: "no reply", status: r.status, detail: JSON.stringify(j).slice(0, 200) }, 502);
    return json({ model, message: { role: "assistant", content: msg.content || "", tool_calls: msg.tool_calls || [] } });
  } catch (e) {
    return json({ error: "chat failed", detail: String(e).slice(0, 160) }, 502);
  } finally { clearTimeout(timer); }
}
