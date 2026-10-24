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
    const room = env.ROOM.get(env.ROOM.idFromName("live"));
    if (url.pathname === "/api/ingest" || url.pathname === "/api/reset") {
      const auth = request.headers.get("authorization") || "";
      if (!env.INGEST_KEY || auth !== `Bearer ${env.INGEST_KEY}`) return json({ error: "unauthorized" }, 401);
      return room.fetch(request);
    }
    if (url.pathname === "/api/live" || url.pathname === "/api/events" || url.pathname === "/api/status") return room.fetch(request);
    if (url.pathname === "/api/analyze" && request.method === "POST") return analyze(request, env);
    return env.ASSETS.fetch(request);
  },
};

export class LiveRoom extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`CREATE TABLE IF NOT EXISTS episodes (id TEXT PRIMARY KEY, start REAL, end REAL, seconds REAL, intense INTEGER, hz REAL, received REAL)`);
      this.lastSeen = (await this.ctx.storage.get("lastSeen")) || null;
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
      const msg = JSON.stringify({
        type: "batch", receivedAt: now, sentAt: body.sentAt || null, live: !!body.live,
        samples: Array.isArray(body.samples) ? body.samples.slice(0, 2000) : [],
        windows: Array.isArray(body.windows) ? body.windows.slice(0, 100) : [],
        events,
      });
      for (const ws of this.ctx.getWebSockets()) { try { ws.send(msg); } catch {} }
      return json({ ok: true, clients: this.ctx.getWebSockets().length });
    }
    if (url.pathname === "/api/events") {
      const since = +(url.searchParams.get("since") || 0);
      const rows = this.ctx.storage.sql.exec(`SELECT id,start,end,seconds,intense,hz FROM episodes WHERE start >= ? ORDER BY start`, since).toArray();
      return json({ episodes: rows.map(r => ({ ...r, intense: !!r.intense })), lastSeen: this.lastSeen });
    }
    if (url.pathname === "/api/status") return json({ lastSeen: this.lastSeen, clients: this.ctx.getWebSockets().length, now: Date.now() / 1000 });
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
