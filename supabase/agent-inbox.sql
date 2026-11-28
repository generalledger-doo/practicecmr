-- Practice Desk CRM: drop box for the email-sorting agent.
-- Run once in Supabase: SQL Editor -> New query -> paste this file -> Run (safe to run again).
-- The agent can only ADD an import to the queue with its own key. It cannot read or change anything.
-- Members see the queue in the CRM and add it with one click.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.import_queue (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  source      text not null default 'agent',
  summary     text,
  payload     jsonb not null,
  status      text not null default 'pending' check (status in ('pending','imported','dismissed')),
  handled_by  uuid,
  handled_at  timestamptz
);

-- agent keys: only a SHA-256 hash is stored; the key itself is shown once when created
create table if not exists public.agent_tokens (
  token_hash  text primary key,
  label       text not null,
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  last_used   timestamptz
);

alter table public.import_queue enable row level security;
alter table public.agent_tokens enable row level security;
revoke all on public.import_queue, public.agent_tokens from anon, authenticated;
grant select, update on public.import_queue to authenticated;

drop policy if exists "members read queue" on public.import_queue;
drop policy if exists "members handle queue" on public.import_queue;
create policy "members read queue" on public.import_queue for select to authenticated using (public.can_use());
create policy "members handle queue" on public.import_queue for update to authenticated using (public.can_use()) with check (public.can_use());

-- which period each batch covers, so every run continues where the last one stopped
alter table public.import_queue add column if not exists period_from timestamptz;
alter table public.import_queue add column if not exists period_to   timestamptz;

-- checks the key in the "x-agent-token" header; raises if missing or not active
create or replace function public.agent_key_ok() returns void
language plpgsql security definer set search_path = public, extensions as $$
declare
  tok text := coalesce(current_setting('request.headers', true)::json ->> 'x-agent-token', '');
begin
  if length(tok) < 32 then raise exception 'missing agent key' using errcode = '28000'; end if;
  update public.agent_tokens set last_used = now() where token_hash = encode(extensions.digest(tok, 'sha256'), 'hex') and active;
  if not found then raise exception 'invalid agent key' using errcode = '28000'; end if;
end $$;
revoke all on function public.agent_key_ok() from public, anon, authenticated;

-- The agent calls this (POST /rest/v1/rpc/submit_import) with its key in the "x-agent-token" header.
drop function if exists public.submit_import(jsonb, text);
create or replace function public.submit_import(p_payload jsonb, p_summary text default null,
                                                p_period_from timestamptz default null, p_period_to timestamptz default null)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare new_id bigint;
begin
  perform public.agent_key_ok();
  if pg_column_size(p_payload) > 5000000 then raise exception 'payload too large'; end if;
  if jsonb_typeof(p_payload -> 'data') is distinct from 'object' then raise exception 'payload must contain "data"'; end if;
  insert into public.import_queue (source, summary, payload, period_from, period_to)
  values ('agent', left(p_summary, 2000), p_payload, p_period_from, coalesce(p_period_to, now()))
  returning id into new_id;
  return new_id;
end $$;
revoke all on function public.submit_import(jsonb, text, timestamptz, timestamptz) from public;
grant execute on function public.submit_import(jsonb, text, timestamptz, timestamptz) to anon, authenticated;

-- Before a run the agent asks where the last check ended and which Gmail threads it already delivered
-- (last 120 days). It learns nothing else about the CRM.
create or replace function public.agent_state()
returns json language plpgsql security definer set search_path = public, extensions as $$
declare last_to timestamptz; threads text[];
begin
  perform public.agent_key_ok();
  select coalesce(max(period_to), max(created_at)) into last_to from public.import_queue;
  select coalesce(array_agg(distinct t), '{}') into threads from (
    select coalesce(r.value ->> 'gmailThreadId', substr(r.key, 4)) as t
    from public.import_queue q,
         lateral (select * from jsonb_each(coalesce(q.payload -> 'data' -> 'requests', '{}'))
                  union all select * from jsonb_each(coalesce(q.payload -> 'data' -> 'leads', '{}'))) r
    where q.created_at > now() - interval '120 days') x where t is not null and t <> '';
  return json_build_object('last_checked_to', last_to, 'delivered_thread_ids', threads);
end $$;
revoke all on function public.agent_state() from public;
grant execute on function public.agent_state() to anon, authenticated;

-- Create a key (run in the SQL Editor only): select public.create_agent_token('Claude email sorting');
-- The key is shown once; store it as the agent's credential. Switch a key off:
--   update public.agent_tokens set active = false where label = 'Claude email sorting';
create or replace function public.create_agent_token(p_label text)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare tok text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  insert into public.agent_tokens (token_hash, label) values (encode(extensions.digest(tok, 'sha256'), 'hex'), p_label);
  return tok;
end $$;
revoke all on function public.create_agent_token(text) from public, anon, authenticated;
