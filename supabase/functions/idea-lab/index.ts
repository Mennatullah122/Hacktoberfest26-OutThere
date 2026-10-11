// Supabase Edge Function (Deno). Secrets: AI_BASE_URL, AI_API_KEY, AI_MODEL — any OpenAI-compatible endpoint
// serving an open-weight model. Example (Gemma on Hugging Face Inference Providers):
//   AI_BASE_URL=https://router.huggingface.co/v1  AI_MODEL=google/gemma-3-27b-it  AI_API_KEY=<HF token>
// or your own Ollama/vLLM server. Swap the model by changing these variables; no code change.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.0';
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': 'authorization, content-type, apikey' };
const SAFE = ['Meet in a public, open area; participation is voluntary.', 'Stay on public paths; never enter restricted areas.', 'No climbing, picking plants or disturbing wildlife.'];
const parseJSON = (t: string) => { const a = t.indexOf('{'), b = t.lastIndexOf('}'); if (a < 0 || b < a) return null; try { return JSON.parse(t.slice(a, b + 1)); } catch { return null; } };
const strs = (v: unknown, n: number) => Array.isArray(v) && v.length >= n && v.length <= 12 && v.every((x) => typeof x === 'string' && x.length < 400);
function valid(r: any) {
  const s = (k: string) => typeof r?.[k] === 'string' && r[k].length > 0 && r[k].length < 600;
  if (!['title', 'desc', 'objective', 'closing'].every(s) || !strs(r.steps, 3) || !strs(r.prompts, 1) || !strs(r.variations, 1) || !strs(r.access, 1)) return null;
  return { ...r, safety: [...(strs(r.safety, 1) ? r.safety : []), ...SAFE] };
}
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  const j = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...cors, 'content-type': 'application/json' } });
  const sb = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, { global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } } });
  const { data: { user } } = await sb.auth.getUser();
  if (!user) return j({ error: 'sign in required' }, 401);
  const since = new Date(Date.now() - 3600e3).toISOString();                      // rate limit: 10/hour/user
  const { count } = await sb.from('ai_activity_generations').select('id', { count: 'exact', head: true }).eq('user_id', user.id).gte('created_at', since);
  if ((count ?? 0) >= 10) return j({ error: 'rate limit: try again later' }, 429);
  let params: unknown;
  try { params = await req.json(); } catch { return j({ error: 'invalid JSON body' }, 400); }
  if (JSON.stringify(params).length > 2000) return j({ error: 'request too large' }, 413);
  let plan = null, source = 'template', model = null;
  try {
    const base = Deno.env.get('AI_BASE_URL'), key = Deno.env.get('AI_API_KEY'), m = Deno.env.get('AI_MODEL');
    if (!base || !key || !m) throw new Error('AI not configured');
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 25000);
    const res = await fetch(`${base}/chat/completions`, { method: 'POST', signal: ctl.signal, headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
      body: JSON.stringify({ model: m, temperature: 0.7, max_tokens: 900, messages: [
        { role: 'user', content: 'You design safe public-park social activities in Cairo. Never suggest trespassing, danger, disturbing wildlife, damaging plants or restricted areas. Reply ONLY with JSON: title, desc, objective, duration, size, materials (strings); steps, prompts, variations, access, safety (string arrays); closing (string). Never invent venue names, hours, fees or crowd levels.\n\nRequest: ' + JSON.stringify(params) }] }) });
    clearTimeout(t);
    if (!res.ok) throw new Error('provider ' + res.status);
    plan = valid(parseJSON(String((await res.json()).choices?.[0]?.message?.content ?? '')));
    if (plan) { source = 'model'; model = m; }
  } catch (_e) { /* fall through to template flag */ }
  await sb.from('ai_activity_generations').insert({ user_id: user.id, input_parameters: params, generated_output: plan, model_identifier: model });
  return j({ plan, source, model });   // plan:null + source:'template' => client shows its curated template, labelled as such
});
