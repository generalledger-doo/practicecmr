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

-- The agent calls this (POST /rest/v1/rpc/submit_import) with its key in the "x-agent-token" header.
create or replace function public.submit_import(p_payload jsonb, p_summary text default null)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare
  tok text := coalesce(current_setting('request.headers', true)::json ->> 'x-agent-token', '');
  h text;
  new_id bigint;
begin
  if length(tok) < 32 then raise exception 'missing agent key' using errcode = '28000'; end if;
  h := encode(extensions.digest(tok, 'sha256'), 'hex');
  update public.agent_tokens set last_used = now() where token_hash = h and active;
  if not found then raise exception 'invalid agent key' using errcode = '28000'; end if;
  if pg_column_size(p_payload) > 5000000 then raise exception 'payload too large'; end if;
  if jsonb_typeof(p_payload -> 'data') is distinct from 'object' then raise exception 'payload must contain "data"'; end if;
  insert into public.import_queue (source, summary, payload) values ('agent', left(p_summary, 2000), p_payload) returning id into new_id;
  return new_id;
end $$;
revoke all on function public.submit_import(jsonb, text) from public;
grant execute on function public.submit_import(jsonb, text) to anon, authenticated;

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
