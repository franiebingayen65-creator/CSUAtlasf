-- Do not announce an evaluation update when only metadata changed or the
-- committed score values stayed the same.
create or replace function public.notify_evaluation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  organization_name text;
begin
  if TG_OP = 'UPDATE'
     and NEW.score_i is not distinct from OLD.score_i
     and NEW.score_ii is not distinct from OLD.score_ii
     and NEW.score_iii is not distinct from OLD.score_iii
     and NEW.score_iv is not distinct from OLD.score_iv
     and NEW.score_v is not distinct from OLD.score_v
     and NEW.score_vi is not distinct from OLD.score_vi
     and NEW.score_vii is not distinct from OLD.score_vii
     and NEW.score_viii is not distinct from OLD.score_viii
     and NEW.score_ix is not distinct from OLD.score_ix
     and NEW.score_x is not distinct from OLD.score_x then
    return NEW;
  end if;

  select o.name into organization_name
  from public.organizations o
  where o.id = NEW.organization_id;

  insert into public.notifications(recipient_id, title, body, status)
  select p.id,
         'Evaluation scores posted',
         'Scores for ' || coalesce(organization_name, 'your organization') ||
           ' are available for SY ' || NEW.school_year || '.',
         'Scores Posted'
  from public.profiles p
  where p.organization_id = NEW.organization_id
    and p.role in ('President', 'Adviser')
    and (auth.uid() is null or p.id <> auth.uid());
  return NEW;
end;
$$;
