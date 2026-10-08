# Supabase Database Schema: CSU Atlas

This document contains the complete SQL schema required for the CSU Atlas application, based on the implementation in `lib/admin_dashboard.dart` and `lib/org_dashboard.dart`.

## 1. Tables

### Organizations
```sql
create table organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null, -- 'Specialized Organization', 'College Student Council', etc.
  created_at timestamptz default now()
);
```

### Profiles
```sql
create table profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text,
  email text,
  role text not null check (role in ('Admin', 'President', 'Adviser')),
  organization_id uuid references organizations(id),
  created_at timestamptz default now()
);
```

### Activities (GPOA)
```sql
create table activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  title text not null,
  subtitle text, -- Activity Type
  description text,
  sdgs text,
  objectives text,
  outcome text,
  participants text,
  time_frame text, -- Format: "08:00 AM - 10:00 AM"
  delivery_strategy text,
  persons_involved text,
  facilities_materials text,
  budget_allocation text,
  status text default 'Pending' check (status in ('Pending', 'Endorsed', 'Approved', 'Awaiting Date Approval', 'Needs Revision', 'Scheduled', 'Completed', 'Rejected')),
  remarks text, -- Feedback from Admin/Adviser
  proposed_date timestamptz,
  created_at timestamptz default now(),
  report_url text, -- Legacy direct file link
  report_status text check (report_status in ('Pending', 'Approved'))
);
```

### Organization Evaluations (Scoring)
```sql
create table organization_evaluations (
  organization_id uuid references organizations(id) on delete cascade,
  school_year text not null, -- e.g., '2025-2026'
  score_i float8 default 0,
  score_ii float8 default 0,
  score_iii float8 default 0,
  score_iv float8 default 0,
  score_v float8 default 0,
  score_vi float8 default 0,
  score_vii float8 default 0,
  score_viii float8 default 0,
  score_ix float8 default 0,
  score_x float8 default 0,
  grand_total float8 default 0,
  adjectival_rating text,
  updated_at timestamptz default now(),
  primary key (organization_id, school_year)
);
```

### Accomplishment Reports
```sql
create table accomplishment_reports (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  activity_id uuid references activities(id) on delete cascade,
  title text not null,
  summary text,
  attachments text[] default '{}', -- Array of public URLs
  status text default 'Pending' check (status in ('Pending', 'Approved', 'Needs Revision')),
  report_date timestamptz default now()
);
```

### Org Officers
```sql
create table org_officers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references organizations(id) on delete cascade,
  full_name text not null,
  position text not null,
  created_at timestamptz default now()
);
```

## 2. Storage Buckets

Ensure you have a public bucket named **`documents`** in Supabase Storage.
The app uploads files to:
- `reports/`: Accomplishment report attachments.

## 3. Row Level Security (RLS) - Recommended

```sql
-- Enable RLS on all tables
alter table profiles enable row level security;
alter table activities enable row level security;
-- ... repeat for other tables

-- Example Policy: Profiles are viewable by everyone
create policy "Public profiles are viewable by everyone." on profiles
  for select using (true);

-- Example Policy: Users can update their own profile
create policy "Users can update own profile." on profiles
  for update using (auth.uid() = id);

-- Example Policy: Activities are viewable by everyone
create policy "Activities are viewable by everyone." on activities
  for select using (true);

-- Example Policy: Only President can insert activities for their org
create policy "Presidents can insert activities." on activities
  for insert with check (
    exists (
      select 1 from profiles
      where profiles.id = auth.uid()
      and profiles.organization_id = activities.organization_id
      and profiles.role = 'President'
    )
  );
```
