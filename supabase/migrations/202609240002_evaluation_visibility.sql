-- Keep evaluation rows private to admins and the owning organization.
-- The rank RPC below returns only the signed-in organization's score/standing.
alter table public.organization_evaluations enable row level security;

drop policy if exists "Admins manage organization evaluations"
  on public.organization_evaluations;
create policy "Admins manage organization evaluations"
  on public.organization_evaluations
  for all to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'Admin'
  ))
  with check (exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'Admin'
  ));

drop policy if exists "Organizations read their own evaluation"
  on public.organization_evaluations;
create policy "Organizations read their own evaluation"
  on public.organization_evaluations
  for select to authenticated
  using (exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('President', 'Adviser')
      and p.organization_id = organization_evaluations.organization_id
  ));

create or replace function public.get_my_organization_ranking(p_school_year text)
returns table (
  organization_id uuid,
  grand_total numeric,
  adjectival_rating text,
  standing bigint,
  total_organizations bigint
)
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select e.organization_id,
           e.grand_total::numeric as grand_total,
           e.adjectival_rating::text as adjectival_rating,
           rank() over (order by e.grand_total desc)::bigint as standing,
           count(*) over ()::bigint as total_organizations
    from public.organization_evaluations e
    where e.school_year = p_school_year
  ), my_org as (
    select p.organization_id
    from public.profiles p
    where p.id = auth.uid()
      and p.role in ('President', 'Adviser')
  )
  select ranked.organization_id, ranked.grand_total, ranked.adjectival_rating,
         ranked.standing, ranked.total_organizations
  from ranked join my_org using (organization_id);
$$;

revoke all on function public.get_my_organization_ranking(text) from public;
grant execute on function public.get_my_organization_ranking(text) to authenticated;

notify pgrst, 'reload schema';
