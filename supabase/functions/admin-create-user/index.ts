import { corsHeaders, json, requireAdmin } from '../_shared/admin.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const a = await requireAdmin(req);
  if (a.error) return a.error;

  const { fullName, email, password, role, organizationId } = await req.json();
  if (!fullName || !email || !password || password.length < 8) {
    return json({ error: 'Full name, email, and a password of at least 8 characters are required' }, 400);
  }
  if (!['Admin', 'Adviser', 'President'].includes(role)) {
    return json({ error: 'Invalid role' }, 400);
  }

  const { data, error } = await a.admin!.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName },
  });
  if (error || !data.user) return json({ error: error?.message ?? 'Could not create user' }, 400);

  const { error: pErr } = await a.admin!.from('profiles').upsert({
    id: data.user.id,
    full_name: fullName,
    email,
    role,
    organization_id: role === 'Admin' ? null : organizationId,
  });
  if (pErr) {
    await a.admin!.auth.admin.deleteUser(data.user.id);
    return json({ error: pErr.message }, 400);
  }
  return json({ success: true, id: data.user.id });
});