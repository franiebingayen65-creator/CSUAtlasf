import { corsHeaders, json, requireAdmin } from '../_shared/admin.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const a = await requireAdmin(req);
  if (a.error) return a.error;

  const body = await req.json();
  const userId = body.userId;
  const newPassword = body.newPassword || body.password;
  if (!userId || !newPassword || newPassword.length < 8) {
    return json({ error: 'userId and a password of at least 8 characters are required' }, 400);
  }
  const { error } = await a.admin!.auth.admin.updateUserById(userId, { password: newPassword });
  if (error) return json({ error: error.message }, 400);
  return json({ success: true });
});