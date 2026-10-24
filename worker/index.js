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
  const system = `You are the trigger-finding assistant inside Eczema Twin. You get a daily log (scratch minutes measured by an Apple Watch, sleep, humidity, exposures). Find likely personal flare triggers, considering 1-3 day lags and overlapping changes. Use confidence low/medium/high honestly; never diagnose. Reply with JSON only: {"summary": str (2-3 plain sentences), "suspects": [{"title": str, "confidence": "low|medium|high", "lag": str, "evidence": str}], "cannotSeparate": [str], "nextStep": str}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 25000);
  try {
    const r = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST", signal: controller.signal,
      headers: { authorization: `Bearer ${env.OPENROUTER_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ model, max_tokens: 1200, temperature: 0.4, messages: [{ role: "system", content: system }, { role: "user", content: JSON.stringify(body.log || {}) }] }),
    });
    const j = await r.json();
    let text = (j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content) || "";
    text = text.trim().replace(/^```(json)?/, "").replace(/```$/, "").trim();
    return json({ model, caseFile: JSON.parse(text) });
  } catch (e) {
    return json({ error: "analysis failed", detail: String(e).slice(0, 120) }, 502);
  } finally { clearTimeout(timer); }
}
