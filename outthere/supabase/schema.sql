-- OutThere schema (optional Supabase backend). Not yet run against a live project: review, then paste into the Supabase SQL editor.
-- Note: activity_counts and public_profiles are views that run with the owner's rights on purpose (they expose counts / names only).
create extension if not exists pgcrypto;

create table profiles(
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 2 and 50),
  avatar_url text, preferred_neighborhoods text[] default '{}', interests text[] default '{}',
  preferred_categories text[] default '{}', languages jsonb default '{}', max_group_size int,
  created_at timestamptz default now(), updated_at timestamptz default now());

create table venues(
  id uuid primary key default gen_random_uuid(), name text not null, neighborhood text not null,
  general_address text, latitude numeric, longitude numeric,
  verification_status text not null default 'unverified' check (verification_status in ('unverified','verified')),
  source_url text, last_verified_at timestamptz, created_at timestamptz default now(),
  check (verification_status='verified' or (latitude is null and longitude is null)));

create table activities(
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references profiles(id) on delete cascade,
  venue_id uuid references venues(id), title text not null check (char_length(title) between 4 and 80),
  description text not null check (char_length(description) >= 20),
  category text not null check (category in ('Games','Language Exchange','Outdoor Adventures','Walking and Nature')),
  neighborhood text not null, starts_at timestamptz not null,
  duration_minutes int not null check (duration_minutes between 15 and 480),
  capacity int not null check (capacity between 2 and 30),
  language_level text, materials text, accessibility text, rules text,
  is_demo boolean not null default false,
  status text not null default 'open' check (status in ('open','cancelled')),
  created_at timestamptz default now(), updated_at timestamptz default now());
create index on activities(starts_at); create index on activities(category, neighborhood);

create table activity_participants(
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references activities(id) on delete cascade,
  user_id uuid not null references profiles(id) on delete cascade,
  participation_status text not null default 'joined' check (participation_status in ('joined')),
  created_at timestamptz default now(),
  unique (activity_id, user_id));          -- blocks duplicate joins

create table activity_reports(
  id uuid primary key default gen_random_uuid(), reporter_id uuid not null references profiles(id),
  activity_id uuid references activities(id), reported_user_id uuid references profiles(id),
  reason text not null, description text, status text not null default 'open', created_at timestamptz default now(),
  check (activity_id is not null or reported_user_id is not null));

create table ai_activity_generations(
  id uuid primary key default gen_random_uuid(), user_id uuid references profiles(id) on delete set null,
  input_parameters jsonb not null, generated_output jsonb, model_identifier text, created_at timestamptz default now());

-- Atomic join: row lock serialises concurrent joins, so capacity cannot be exceeded.
create function join_activity(p_activity uuid) returns void language plpgsql security definer set search_path=public as $$
declare a activities%rowtype; n int;
begin
  if auth.uid() is null then raise exception 'sign in required'; end if;
  select * into a from activities where id=p_activity for update;
  if not found then raise exception 'activity not found'; end if;
  if a.status='cancelled' then raise exception 'activity cancelled'; end if;
  if a.starts_at + make_interval(mins=>a.duration_minutes) < now() then raise exception 'activity ended'; end if;
  select count(*) into n from activity_participants where activity_id=p_activity;
  if n >= a.capacity then raise exception 'activity full'; end if;
  insert into activity_participants(activity_id,user_id) values(p_activity,auth.uid()); -- unique violation => duplicate
end $$;
create function leave_activity(p_activity uuid) returns void language sql security definer set search_path=public as
$$ delete from activity_participants where activity_id=p_activity and user_id=auth.uid() $$;
-- Public counts without exposing who joined
create view activity_counts as select activity_id, count(*)::int as joined from activity_participants group by activity_id;

alter table profiles enable row level security; alter table venues enable row level security;
alter table activities enable row level security; alter table activity_participants enable row level security;
alter table activity_reports enable row level security; alter table ai_activity_generations enable row level security;

create policy "profiles own read" on profiles for select using (auth.uid()=id);
create policy "profiles own write" on profiles for all using (auth.uid()=id) with check (auth.uid()=id);
create policy "venues public read" on venues for select using (true);
create policy "activities public read" on activities for select using (true);
create policy "activities host insert" on activities for insert with check (auth.uid()=host_id and is_demo=false);
create policy "activities host update" on activities for update using (auth.uid()=host_id) with check (auth.uid()=host_id and is_demo=false);
create policy "participants see own" on activity_participants for select using (user_id=auth.uid());
-- no insert/delete policies: writes go only through join_activity / leave_activity
create policy "reports insert own" on activity_reports for insert with check (reporter_id=auth.uid());
create policy "reports read own" on activity_reports for select using (reporter_id=auth.uid());
create policy "ai own read" on ai_activity_generations for select using (user_id=auth.uid());
-- FIX: the Edge Function inserts as the signed-in user; without this policy the insert failed silently and the rate limit never counted anything.
create policy "ai own insert" on ai_activity_generations for insert with check (user_id=auth.uid());
-- FIX: Postgres grants EXECUTE to PUBLIC by default; restrict to signed-in users.
revoke execute on function join_activity(uuid), leave_activity(uuid) from public, anon;
grant execute on function join_activity(uuid), leave_activity(uuid) to authenticated;

-- FIX: activities.host_id references profiles, but nothing created a profile row, so the first "Host" insert failed.
create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into profiles(id, display_name)
  values (new.id, coalesce(nullif(left(new.raw_user_meta_data->>'display_name',50),''), 'Member'))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();

-- FIX: profiles are private (good), but activity cards need the host's display name. Expose only id + name.
create view public_profiles as select id, display_name from profiles;
grant select on public_profiles to anon, authenticated;
grant select on activity_counts to anon, authenticated;
-- Retention (run on a schedule): delete from ai_activity_generations where created_at < now()-interval '30 days';
