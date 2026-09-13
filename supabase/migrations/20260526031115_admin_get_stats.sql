create schema if not exists private;

revoke all on schema private from public;
revoke all on schema private from anon;
revoke all on schema private from authenticated;

create or replace function private.admin_get_stats_internal()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if (select auth.uid()) is null
    or coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'admin'
  then
    raise exception 'not authorized' using errcode = '42501';
  end if;

  with daily as (
    select
      gs.day::date as day,
      coalesce(count(r.*), 0)::int as cnt
    from generate_series(current_date - 13, current_date, interval '1 day') as gs(day)
    left join public.updrs_results r
      on r.tested_at::date = gs.day::date
    group by gs.day
    order by gs.day
  ),
  by_type as (
    select
      coalesce(r.factors ->> 'test_type', 'finger') as type,
      count(*)::int as cnt
    from public.updrs_results r
    group by 1
    order by 2 desc, 1 asc
  ),
  score_dist as (
    select
      scores.score,
      coalesce(count(r.*), 0)::int as cnt
    from generate_series(0, 4) as scores(score)
    left join public.updrs_results r
      on r.score = scores.score
    group by scores.score
    order by scores.score
  )
  select jsonb_build_object(
    'total_users', (select count(*)::int from auth.users),
    'unique_users', (select count(distinct r.user_id)::int from public.updrs_results r where r.user_id is not null),
    'total_assessments', (select count(*)::int from public.updrs_results),
    'daily_14d', coalesce(
      (select jsonb_agg(jsonb_build_object('day', to_char(d.day, 'YYYY-MM-DD'), 'cnt', d.cnt) order by d.day) from daily d),
      '[]'::jsonb
    ),
    'by_type', coalesce(
      (select jsonb_agg(jsonb_build_object('type', t.type, 'cnt', t.cnt) order by t.cnt desc, t.type asc) from by_type t),
      '[]'::jsonb
    ),
    'score_dist', coalesce(
      (select jsonb_agg(jsonb_build_object('score', s.score, 'cnt', s.cnt) order by s.score) from score_dist s),
      '[]'::jsonb
    )
  ) into result;

  return result;
end;
$$;

revoke all on function private.admin_get_stats_internal() from public;
revoke all on function private.admin_get_stats_internal() from anon;
revoke all on function private.admin_get_stats_internal() from authenticated;
grant usage on schema private to authenticated;
grant execute on function private.admin_get_stats_internal() to authenticated;

create or replace function public.admin_get_stats()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select private.admin_get_stats_internal();
$$;

revoke all on function public.admin_get_stats() from public;
grant execute on function public.admin_get_stats() to authenticated;
