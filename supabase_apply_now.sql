-- PostPilot: run this ONCE in Supabase Dashboard -> SQL Editor. Safe to re-run.
-- It contains every live-database change made after the original team schema.

-- 1) Creating a team collection failed with 42501 ("new row violates
--    row-level security policy"). `insert ... returning` checks the SELECT
--    policy on the new row before the after-insert trigger has added the
--    owner's membership row, so owners must be able to see their own rows.
drop policy if exists "members can view collections" on public.cloud_collections;

create policy "members can view collections" on public.cloud_collections
  for select to authenticated
  using (owner_id = (select auth.uid()) or private.is_collection_member(id));

-- 2) Deleted folders/requests never disappeared from teammates' screens.
--    Realtime DELETE events only carry the primary key by default, so the
--    app's collection_id filter never matched. `full` includes every column.
alter table public.cloud_folders replica identity full;
alter table public.cloud_requests replica identity full;
