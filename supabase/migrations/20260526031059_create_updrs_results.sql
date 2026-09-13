create extension if not exists pgcrypto;

create table if not exists public.updrs_results (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  tested_at timestamptz not null default timezone('utc', now()),
  mode text not null default 'live' check (mode in ('live', 'video')),
  score smallint not null check (score between 0 and 4),
  raw_score numeric,
  n_taps integer,
  frequency numeric,
  arrests integer,
  iti_cv numeric,
  max_amplitude numeric,
  fatigability numeric,
  confidence text not null check (confidence in ('HIGH', 'MEDIUM', 'LOW')),
  duration_sec numeric,
  factors jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists updrs_results_user_tested_idx
  on public.updrs_results (user_id, tested_at desc);

create index if not exists updrs_results_tested_idx
  on public.updrs_results (tested_at desc);

create index if not exists updrs_results_type_idx
  on public.updrs_results ((coalesce(factors ->> 'test_type', 'finger')));

alter table public.updrs_results enable row level security;

drop policy if exists updrs_results_select_own on public.updrs_results;
create policy updrs_results_select_own
on public.updrs_results
for select
to authenticated
using (auth.uid() = user_id);

drop policy if exists updrs_results_insert_own on public.updrs_results;
create policy updrs_results_insert_own
on public.updrs_results
for insert
to authenticated
with check (auth.uid() = user_id);

drop policy if exists updrs_results_update_own on public.updrs_results;
create policy updrs_results_update_own
on public.updrs_results
for update
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

revoke all on table public.updrs_results from anon;
grant select, insert, update on table public.updrs_results to authenticated;
