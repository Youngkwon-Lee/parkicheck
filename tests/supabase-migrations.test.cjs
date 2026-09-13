const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const readMigration = (name) => fs.readFileSync(path.join(root, 'supabase', 'migrations', name), 'utf8');

test('UPDRS results use owner-scoped RLS and explicit Data API grants', () => {
  const sql = readMigration('20260526031059_create_updrs_results.sql');

  assert.match(sql, /alter table public\.updrs_results enable row level security/i);
  assert.match(sql, /to authenticated\s+using \(auth\.uid\(\) = user_id\)/i);
  assert.match(sql, /for update[\s\S]*using \(auth\.uid\(\) = user_id\)[\s\S]*with check \(auth\.uid\(\) = user_id\)/i);
  assert.match(sql, /revoke all on table public\.updrs_results from anon/i);
  assert.match(sql, /grant select, insert, update on table public\.updrs_results to authenticated/i);
  assert.doesNotMatch(sql, /grant[^;]*delete/i);
});

test('admin stats authorize through app metadata inside a private definer', () => {
  const sql = readMigration('20260526031115_admin_get_stats.sql');

  assert.match(sql, /function private\.admin_get_stats_internal\(\)/i);
  assert.match(sql, /security definer\s+set search_path = ''/i);
  assert.match(sql, /auth\.uid\(\)/i);
  assert.match(sql, /auth\.jwt\(\) -> 'app_metadata' ->> 'role'/i);
  assert.doesNotMatch(sql, /user_metadata|admin_email|@[a-z0-9.-]+/i);
  assert.match(sql, /revoke all on function private\.admin_get_stats_internal\(\) from public/i);
  assert.match(sql, /grant execute on function private\.admin_get_stats_internal\(\) to authenticated/i);
  assert.match(sql, /function public\.admin_get_stats\(\)[\s\S]*security invoker[\s\S]*private\.admin_get_stats_internal\(\)/i);
  assert.doesNotMatch(sql, /function public\.admin_get_stats\(\)[\s\S]*security definer/i);
});
