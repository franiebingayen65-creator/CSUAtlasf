-- Notify the opposite side of each workflow action. Notifications are stored
-- in the in-app inbox and streamed through Supabase Realtime.

create or replace function public.notify_activity_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  event_status text;
  notification_title text;
  notification_body text;
begin
  if TG_OP = 'UPDATE' and to_jsonb(NEW) = to_jsonb(OLD) then
    return NEW;
  end if;

  select p.role into actor_role
  from public.profiles p
  where p.id = auth.uid();

  event_status := coalesce(NEW.status, 'Pending');
  if TG_OP = 'INSERT' then
    notification_title := 'New GPOA submission';
    notification_body := coalesce(NEW.title, 'GPOA activity') || ' was submitted for review.';
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, event_status
    from public.profiles p
    where p.role = 'Admin'
      and (auth.uid() is null or p.id <> auth.uid());
    return NEW;
  end if;

  if NEW.is_archived is distinct from OLD.is_archived then
    notification_title := case when NEW.is_archived then 'GPOA archived' else 'GPOA restored' end;
    notification_body := coalesce(NEW.title, 'GPOA activity') ||
      case when NEW.is_archived then ' was archived.' else ' was restored from the archive.' end;
  elsif NEW.status is distinct from OLD.status then
    notification_title := 'GPOA status updated';
    notification_body := coalesce(NEW.title, 'GPOA activity') || ' is now ' || event_status || '.';
  elsif NEW.proposed_date is distinct from OLD.proposed_date then
    notification_title := 'Event date updated';
    notification_body := coalesce(NEW.title, 'GPOA activity') || ' has a proposed date update.';
  elsif NEW.letter_url is distinct from OLD.letter_url then
    notification_title := 'Request letter updated';
    notification_body := 'The request letter for ' || coalesce(NEW.title, 'a GPOA activity') || ' was uploaded or changed.';
  else
    notification_title := 'GPOA updated';
    notification_body := coalesce(NEW.title, 'GPOA activity') || ' details were updated.';
  end if;

  if actor_role = 'Admin' then
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, event_status
    from public.profiles p
    where p.organization_id = NEW.organization_id
      and p.role in ('President', 'Adviser')
      and p.id <> auth.uid();
  else
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, event_status
    from public.profiles p
    where p.role = 'Admin'
      and (auth.uid() is null or p.id <> auth.uid());
  end if;
  return NEW;
end;
$$;

drop trigger if exists activities_notify_change on public.activities;
create trigger activities_notify_change
after insert or update on public.activities
for each row execute function public.notify_activity_change();

create or replace function public.notify_report_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_role text;
  report_status text;
  notification_title text;
  notification_body text;
begin
  if TG_OP = 'UPDATE' and to_jsonb(NEW) = to_jsonb(OLD) then
    return NEW;
  end if;

  select p.role into actor_role
  from public.profiles p
  where p.id = auth.uid();

  report_status := coalesce(NEW.status, 'Pending');
  if TG_OP = 'INSERT' then
    notification_title := 'New accomplishment report';
    notification_body := coalesce(NEW.title, 'Accomplishment report') || ' was submitted for review.';
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, report_status
    from public.profiles p
    where p.role = 'Admin'
      and (auth.uid() is null or p.id <> auth.uid());
    return NEW;
  end if;

  if NEW.is_archived is distinct from OLD.is_archived then
    notification_title := case when NEW.is_archived then 'Report archived' else 'Report restored' end;
    notification_body := coalesce(NEW.title, 'Accomplishment report') ||
      case when NEW.is_archived then ' was archived.' else ' was restored from the archive.' end;
  elsif NEW.status is distinct from OLD.status then
    notification_title := 'Accomplishment report status updated';
    notification_body := coalesce(NEW.title, 'Accomplishment report') || ' is now ' || report_status || '.';
  else
    notification_title := 'Accomplishment report updated';
    notification_body := coalesce(NEW.title, 'Accomplishment report') || ' attachments or details were updated.';
  end if;

  if actor_role = 'Admin' then
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, report_status
    from public.profiles p
    where p.organization_id = NEW.organization_id
      and p.role in ('President', 'Adviser')
      and p.id <> auth.uid();
  else
    insert into public.notifications(recipient_id, title, body, status)
    select p.id, notification_title, notification_body, report_status
    from public.profiles p
    where p.role = 'Admin'
      and (auth.uid() is null or p.id <> auth.uid());
  end if;
  return NEW;
end;
$$;

drop trigger if exists accomplishment_reports_notify_change on public.accomplishment_reports;
create trigger accomplishment_reports_notify_change
after insert or update on public.accomplishment_reports
for each row execute function public.notify_report_change();

create or replace function public.notify_evaluation_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  organization_name text;
begin
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

drop trigger if exists organization_evaluations_notify_change on public.organization_evaluations;
create trigger organization_evaluations_notify_change
after insert or update on public.organization_evaluations
for each row execute function public.notify_evaluation_change();

notify pgrst, 'reload schema';
