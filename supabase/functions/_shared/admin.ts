import { createClient } from 'npm:@supabase/supabase-js@2';

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export async function requireAdmin(req: Request) {
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  const userClient = createClient(url, anon, {
    global: { headers: { Authorization: req.headers.get('Authorization') ?? '' } },
  });
  const { data: { user }, error } = await userClient.auth.getUser();
  if (error || !user) {
    return { error: json({ error: 'Not authenticated' }, 401), admin: null, caller: null };
  }

  const admin = createClient(url, service);
  const { data: profile } = await admin
    .from('profiles').select('role').eq('id', user.id).maybeSingle();
  if (profile?.role !== 'Admin') {
    return { error: json({ error: 'Admin access required' }, 403), admin: null, caller: null };
  }
  return { error: null, admin, caller: user };
}