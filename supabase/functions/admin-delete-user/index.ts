import { corsHeaders, json, requireAdmin } from '../_shared/admin.ts';

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  const a = await requireAdmin(req);
  if (a.error) return a.error;

  const { userId } = await req.json();
  if (!userId) return json({ error: 'userId is required' }, 400);
  if (userId === a.caller!.id) return json({ error: 'You cannot delete your own account' }, 400);

  await a.admin!.from('profiles').delete().eq('id', userId);
  const { error } = await a.admin!.auth.admin.deleteUser(userId);
  if (error) return json({ error: error.message }, 400);
  return json({ success: true });
});