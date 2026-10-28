-- Running Commu check-in: database setup.
-- Paste this whole file into Supabase > SQL Editor > New query, then press Run.
-- Safe to run again: it only creates what is missing.

create extension if not exists pgcrypto;

-- Organisers. The first person to sign up becomes an organiser automatically.
create table if not exists public.admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid());
$$;

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  created_by uuid default auth.uid() references auth.users (id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  group_id uuid references public.groups (id) on delete set null,
  photo text check (photo is null or char_length(photo) < 60000), -- small JPEG data URL
  created_at timestamptz not null default now()
);

create table if not exists public.checkpoints (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  km numeric(6,3) not null check (km > 0 and km <= 100),
  lat double precision,
  lng double precision,
  tag text,
  created_at timestamptz not null default now()
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.checkins (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.profiles (id) on delete cascade,
  checkpoint_id uuid references public.checkpoints (id) on delete set null,
  km numeric(6,3) not null check (km > 0 and km <= 100),
  ts timestamptz not null default now(),
  lat double precision,
  lng double precision,
  acc integer,
  via text check (via in ('nfc', 'button'))
);
create index if not exists checkins_ts_idx on public.checkins (ts desc);

-- First sign-up becomes organiser
create or replace function public.first_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from public.admins) then
    insert into public.admins (user_id) values (new.id);
  end if;
  return new;
end $$;
drop trigger if exists profiles_first_admin on public.profiles;
create trigger profiles_first_admin after insert on public.profiles
  for each row execute function public.first_admin();

-- A check-in always counts the checkpoint's real lap distance and the server time,
-- and the same runner can't log the same checkpoint twice within 45 seconds.
create or replace function public.checkin_guard() returns trigger
language plpgsql security definer set search_path = public as $$
declare cp_km numeric;
begin
  select km into cp_km from public.checkpoints where id = new.checkpoint_id;
  if cp_km is null then raise exception 'Unknown checkpoint'; end if;
  new.km := cp_km;
  if not public.is_admin() then new.ts := now(); end if;
  if exists (select 1 from public.checkins c where c.member_id = new.member_id
             and c.checkpoint_id = new.checkpoint_id and c.ts > new.ts - interval '45 seconds') then
    raise exception 'Already checked in here a moment ago';
  end if;
  return new;
end $$;
drop trigger if exists checkins_guard on public.checkins;
create trigger checkins_guard before insert on public.checkins
  for each row execute function public.checkin_guard();

-- Row level security: signed-in runners read everything, change only their own things.
alter table public.admins enable row level security;
alter table public.groups enable row level security;
alter table public.profiles enable row level security;
alter table public.checkpoints enable row level security;
alter table public.events enable row level security;
alter table public.checkins enable row level security;

drop policy if exists "read admins" on public.admins;
create policy "read admins" on public.admins for select to authenticated using (true);
drop policy if exists "admins manage admins" on public.admins;
create policy "admins manage admins" on public.admins for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read groups" on public.groups;
create policy "read groups" on public.groups for select to authenticated using (true);
drop policy if exists "anyone creates groups" on public.groups;
create policy "anyone creates groups" on public.groups for insert to authenticated with check (true);
drop policy if exists "admins edit groups" on public.groups;
create policy "admins edit groups" on public.groups for update to authenticated using (public.is_admin() or created_by = auth.uid());
drop policy if exists "admins delete groups" on public.groups;
create policy "admins delete groups" on public.groups for delete to authenticated using (public.is_admin());

drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select to authenticated using (true);
drop policy if exists "own profile insert" on public.profiles;
create policy "own profile insert" on public.profiles for insert to authenticated with check (id = auth.uid());
drop policy if exists "own profile update" on public.profiles;
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid() or public.is_admin());
drop policy if exists "admin removes runner" on public.profiles;
create policy "admin removes runner" on public.profiles for delete to authenticated using (public.is_admin());

drop policy if exists "read checkpoints" on public.checkpoints;
create policy "read checkpoints" on public.checkpoints for select to authenticated using (true);
drop policy if exists "admins write checkpoints" on public.checkpoints;
create policy "admins write checkpoints" on public.checkpoints for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read events" on public.events;
create policy "read events" on public.events for select to authenticated using (true);
drop policy if exists "admins write events" on public.events;
create policy "admins write events" on public.events for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read checkins" on public.checkins;
create policy "read checkins" on public.checkins for select to authenticated using (true);
drop policy if exists "own checkins" on public.checkins;
create policy "own checkins" on public.checkins for insert to authenticated with check (member_id = auth.uid());
drop policy if exists "admins delete checkins" on public.checkins;
create policy "admins delete checkins" on public.checkins for delete to authenticated using (public.is_admin());

-- Live updates for the leaderboard and map
do $$
declare t text;
begin
  foreach t in array array['groups','profiles','checkpoints','events','checkins','admins'] loop
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
