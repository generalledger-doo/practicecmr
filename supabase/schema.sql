-- Practice Desk CRM: database setup for Supabase.
-- Run once in the Supabase dashboard: SQL Editor -> New query -> paste this file -> Run.
-- Safe to run again: it only creates what is missing and replaces functions and policies.

-- People allowed to use the CRM. Add a row for each colleague after inviting them (see README).
create table if not exists public.members (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  email      text,
  name       text,
  role       text not null default 'staff' check (role in ('admin','staff')),
  created_at timestamptz not null default now()
);

-- Every CRM record (leads, clients, formations, AML checks, requests, documents, templates, settings)
-- is one row: the collection name, the record id and the record itself as JSON.
create table if not exists public.records (
  coll       text not null,
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  primary key (coll, id)
);

-- Audit trail: every insert, change and delete, with the version before the change.
-- Nothing in the app deletes from here, so a wrong edit or delete can always be recovered.
create table if not exists public.records_history (
  hid        bigint generated always as identity primary key,
  coll       text not null,
  id         text not null,
  op         text not null,          -- insert | update | delete
  data       jsonb,                  -- the record before the change (null for insert)
  changed_at timestamptz not null default now(),
  changed_by uuid
);
create index if not exists records_history_lookup on public.records_history (coll, id, changed_at desc);

-- True when the signed-in user is a member AND has passed two-factor sign-in.
create or replace function public.can_use() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.members where user_id = auth.uid())
     and coalesce(auth.jwt() ->> 'aal', '') = 'aal2';
$$;

create or replace function public.records_stamp() returns trigger
language plpgsql set search_path = public as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end $$;

create or replace function public.records_log() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    insert into public.records_history (coll, id, op, data, changed_by) values (new.coll, new.id, 'insert', null, auth.uid());
  else
    insert into public.records_history (coll, id, op, data, changed_by) values (old.coll, old.id, lower(tg_op), old.data, auth.uid());
  end if;
  return null;
end $$;

drop trigger if exists records_stamp on public.records;
create trigger records_stamp before insert or update on public.records
  for each row execute function public.records_stamp();
drop trigger if exists records_log on public.records;
create trigger records_log after insert or update or delete on public.records
  for each row execute function public.records_log();

-- Row-level security: nobody outside the members list can read or write anything.
alter table public.records         enable row level security;
alter table public.members         enable row level security;
alter table public.records_history enable row level security;

drop policy if exists "members read"   on public.records;
drop policy if exists "members insert" on public.records;
drop policy if exists "members update" on public.records;
drop policy if exists "members delete" on public.records;
create policy "members read"   on public.records for select to authenticated using (public.can_use());
create policy "members insert" on public.records for insert to authenticated with check (public.can_use());
create policy "members update" on public.records for update to authenticated using (public.can_use()) with check (public.can_use());
create policy "members delete" on public.records for delete to authenticated using (public.can_use());

drop policy if exists "own membership" on public.members;
create policy "own membership" on public.members for select to authenticated using (user_id = auth.uid() or public.can_use());

drop policy if exists "members read history" on public.records_history;
create policy "members read history" on public.records_history for select to authenticated using (public.can_use());

revoke all on public.records, public.members, public.records_history from anon;
revoke insert, update, delete on public.members, public.records_history from authenticated;
grant select, insert, update, delete on public.records to authenticated;
grant select on public.members, public.records_history to authenticated;
revoke execute on function public.can_use() from anon;

-- Live sync: send changes to every open copy of the app.
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'records') then
    alter publication supabase_realtime add table public.records;
  end if;
end $$;
