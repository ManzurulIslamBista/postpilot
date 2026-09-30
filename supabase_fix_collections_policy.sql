-- Fix: creating a cloud collection failed with 42501 ("new row violates
-- row-level security policy"). Postgres checks the SELECT policy against the
-- RETURNING row before the after-insert trigger adds the owner's membership
-- row, so the membership-only check always failed. Owners must be allowed to
-- see their own collections directly.
drop policy "members can view collections" on public.cloud_collections;

create policy "members can view collections" on public.cloud_collections
  for select to authenticated
  using (owner_id = (select auth.uid()) or private.is_collection_member(id));
