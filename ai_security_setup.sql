-- Qualisight: AI advisor security setup
-- Run once in Supabase: SQL Editor > New query > paste > Run

-- 1. Subscriptions table. Users can READ their own row, only the server can write it.
--    The Stripe webhook (next fix) will keep this up to date.
create table if not exists public.subscriptions (
  user_id                uuid primary key references auth.users(id) on delete cascade,
  stripe_customer_id     text,
  stripe_subscription_id text,
  status                 text not null default 'inactive',
  current_period_end     timestamptz,
  updated_at             timestamptz not null default now()
);

alter table public.subscriptions enable row level security;

drop policy if exists "read own subscription" on public.subscriptions;
create policy "read own subscription"
  on public.subscriptions for select
  to authenticated
  using (auth.uid() = user_id);
-- No insert/update/delete policies on purpose: browsers cannot change this table.

-- 2. Daily AI usage counter. No policies at all, so only the server can touch it.
create table if not exists public.ai_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  day     date not null,
  count   int  not null default 0,
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

-- 3. Atomic "add one if under the limit". Returns the new count, or NULL if the limit is hit.
create or replace function public.increment_ai_usage(p_user_id uuid, p_limit int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_day   date := (now() at time zone 'America/Toronto')::date;
  v_count int;
begin
  insert into ai_usage (user_id, day, count)
  values (p_user_id, v_day, 1)
  on conflict (user_id, day)
  do update set count = ai_usage.count + 1
  where ai_usage.count < p_limit
  returning count into v_count;

  return v_count;
end;
$$;

revoke all on function public.increment_ai_usage(uuid, int) from public, anon, authenticated;
grant execute on function public.increment_ai_usage(uuid, int) to service_role;
