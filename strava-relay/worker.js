// Kicks Ride — Strava relay (Cloudflare Worker)
// Holds the Strava client secret so the web app never sees it.
// Secrets/variables to set in Cloudflare: STRAVA_CLIENT_ID (text), STRAVA_CLIENT_SECRET (secret)

const ALLOWED = ['https://mrjimcampbell.github.io', 'http://localhost:8642', 'null'];

export default {
  async fetch(req, env) {
    const origin = req.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED.includes(origin) ? origin : ALLOWED[0],
      'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Vary': 'Origin',
    };
    if (req.method === 'OPTIONS') return new Response(null, { headers: cors });
    const url = new URL(req.url);
    const json = (data, status = 200) =>
      new Response(JSON.stringify(data), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

    try {
      // Exchange the one-time code from Strava's login page for tokens
      if (url.pathname === '/token' && req.method === 'POST') {
        const { code } = await req.json();
        return json(...await strava(env, { grant_type: 'authorization_code', code }));
      }
      // Swap an expired access token for a fresh one
      if (url.pathname === '/refresh' && req.method === 'POST') {
        const { refresh_token } = await req.json();
        return json(...await strava(env, { grant_type: 'refresh_token', refresh_token }));
      }
      // Forward an activity upload (multipart form) to Strava
      if (url.pathname === '/upload' && req.method === 'POST') {
        const r = await fetch('https://www.strava.com/api/v3/uploads', {
          method: 'POST',
          headers: { Authorization: req.headers.get('Authorization') || '' },
          body: await req.formData(),
        });
        return json(await r.json(), r.status);
      }
      // Check how an upload is getting on
      const m = url.pathname.match(/^\/upload\/(\d+)$/);
      if (m && req.method === 'GET') {
        const r = await fetch(`https://www.strava.com/api/v3/uploads/${m[1]}`, {
          headers: { Authorization: req.headers.get('Authorization') || '' },
        });
        return json(await r.json(), r.status);
      }
      if (url.pathname === '/') return json({ ok: true, service: 'kicks-ride-strava' });
      return json({ error: 'not found' }, 404);
    } catch (e) {
      return json({ error: String(e && e.message || e) }, 500);
    }
  },
};

async function strava(env, params) {
  const r = await fetch('https://www.strava.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ client_id: env.STRAVA_CLIENT_ID, client_secret: env.STRAVA_CLIENT_SECRET, ...params }),
  });
  const d = await r.json();
  if (!r.ok) return [d, r.status];
  return [{ access_token: d.access_token, refresh_token: d.refresh_token, expires_at: d.expires_at,
            athlete: d.athlete ? { firstname: d.athlete.firstname } : undefined }, 200];
}
