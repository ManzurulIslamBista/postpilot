-- PostPilot team-collaboration schema.
-- Run this once in your Supabase project's Dashboard -> SQL Editor.
-- Safe to re-run only after dropping the objects below (it is not idempotent).

create schema if not exists private;

create type public.member_role as enum ('owner', 'editor', 'viewer');

create table public.cloud_collections (
  id bigint generated always as identity primary key,
  name text not null,
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.collection_members (
  collection_id bigint not null references public.cloud_collections (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role public.member_role not null default 'viewer',
  created_at timestamptz not null default now(),
  primary key (collection_id, user_id)
);

create table public.collection_invites (
  id bigint generated always as identity primary key,
  collection_id bigint not null references public.cloud_collections (id) on delete cascade,
  email text not null,
  role public.member_role not null default 'editor',
  invited_by uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  accepted_at timestamptz
);

create table public.cloud_folders (
  id bigint generated always as identity primary key,
  collection_id bigint not null references public.cloud_collections (id) on delete cascade,
  parent_folder_id bigint references public.cloud_folders (id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now()
);

create table public.cloud_requests (
  id bigint generated always as identity primary key,
  collection_id bigint not null references public.cloud_collections (id) on delete cascade,
  folder_id bigint references public.cloud_folders (id) on delete cascade,
  name text not null,
  method text not null default 'GET',
  url text not null default '',
  headers jsonb not null default '[]',
  query_params jsonb not null default '[]',
  body jsonb not null default '{"type":"none"}',
  auth jsonb not null default '{"type":"none"}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index on public.collection_members (user_id);
create index on public.collection_invites (lower(email));
create index on public.cloud_folders (collection_id);
create index on public.cloud_requests (collection_id);

-- updated_at trigger for cloud_requests
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger cloud_requests_set_updated_at
before update on public.cloud_requests
for each row execute function public.set_updated_at();

-- Membership-check helpers, kept in a non-exposed schema so they can only be
-- reached from RLS policies (see supabase skill: SECURITY DEFINER functions
-- in `public` are callable by any authenticated/anon role).
create or replace function private.is_collection_member(p_collection_id bigint)
returns boolean
language sql
security definer
set search_path = ''
stable
as $$
  select exists (
    select 1 from public.collection_members
    where collection_id = p_collection_id
      and user_id = (select auth.uid())
  );
$$;

create or replace function private.collection_role(p_collection_id bigint)
returns public.member_role
language sql
security definer
set search_path = ''
stable
as $$
  select role from public.collection_members
  where collection_id = p_collection_id
    and user_id = (select auth.uid())
  limit 1;
$$;

alter table public.cloud_collections enable row level security;
alter table public.collection_members enable row level security;
alter table public.collection_invites enable row level security;
alter table public.cloud_folders enable row level security;
alter table public.cloud_requests enable row level security;

-- cloud_collections
-- The owner clause is required, not just convenient: `insert ... returning`
-- (what the client's `.insert().select()` does) applies this SELECT policy to
-- the new row BEFORE the after-insert trigger has added the owner's
-- membership row, so a membership-only check rejects every creation.
create policy "members can view collections" on public.cloud_collections
  for select to authenticated
  using (owner_id = (select auth.uid()) or private.is_collection_member(id));

create policy "authenticated users can create collections" on public.cloud_collections
  for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy "owner can update collection" on public.cloud_collections
  for update to authenticated
  using (owner_id = (select auth.uid()))
  with check (owner_id = (select auth.uid()));

create policy "owner can delete collection" on public.cloud_collections
  for delete to authenticated
  using (owner_id = (select auth.uid()));

-- collection_members
create policy "members can view membership" on public.collection_members
  for select to authenticated
  using (private.is_collection_member(collection_id));

create policy "owner can add members" on public.collection_members
  for insert to authenticated
  with check (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

create policy "owner can update member roles" on public.collection_members
  for update to authenticated
  using (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ))
  with check (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

create policy "owner can remove members" on public.collection_members
  for delete to authenticated
  using (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

-- collection_invites
create policy "owner can view invites" on public.collection_invites
  for select to authenticated
  using (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

create policy "invited user can view own invite" on public.collection_invites
  for select to authenticated
  using (lower(email) = lower((select auth.jwt() ->> 'email')));

create policy "owner can create invites" on public.collection_invites
  for insert to authenticated
  with check (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

create policy "owner can delete invites" on public.collection_invites
  for delete to authenticated
  using (exists (
    select 1 from public.cloud_collections c
    where c.id = collection_id and c.owner_id = (select auth.uid())
  ));

-- cloud_folders
create policy "members can view folders" on public.cloud_folders
  for select to authenticated
  using (private.is_collection_member(collection_id));

create policy "editors can insert folders" on public.cloud_folders
  for insert to authenticated
  with check (private.collection_role(collection_id) in ('owner', 'editor'));

create policy "editors can update folders" on public.cloud_folders
  for update to authenticated
  using (private.collection_role(collection_id) in ('owner', 'editor'))
  with check (private.collection_role(collection_id) in ('owner', 'editor'));

create policy "editors can delete folders" on public.cloud_folders
  for delete to authenticated
  using (private.collection_role(collection_id) in ('owner', 'editor'));

-- cloud_requests
create policy "members can view requests" on public.cloud_requests
  for select to authenticated
  using (private.is_collection_member(collection_id));

create policy "editors can insert requests" on public.cloud_requests
  for insert to authenticated
  with check (private.collection_role(collection_id) in ('owner', 'editor'));

create policy "editors can update requests" on public.cloud_requests
  for update to authenticated
  using (private.collection_role(collection_id) in ('owner', 'editor'))
  with check (private.collection_role(collection_id) in ('owner', 'editor'));

create policy "editors can delete requests" on public.cloud_requests
  for delete to authenticated
  using (private.collection_role(collection_id) in ('owner', 'editor'));

-- Self-service invite acceptance (SECURITY DEFINER is required here since a
-- brand-new member has no row in collection_members yet to satisfy the
-- normal insert policy — the function itself enforces that the caller's JWT
-- email matches the invite before doing anything).
create or replace function public.accept_collection_invite(p_invite_id bigint)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
  v_collection_id bigint;
  v_role public.member_role;
begin
  select email, collection_id, role into v_email, v_collection_id, v_role
  from public.collection_invites
  where id = p_invite_id and accepted_at is null;

  if v_email is null then
    raise exception 'Invite not found or already accepted';
  end if;

  if lower(v_email) <> lower((select auth.jwt() ->> 'email')) then
    raise exception 'This invite is not for your account';
  end if;

  insert into public.collection_members (collection_id, user_id, role)
  values (v_collection_id, (select auth.uid()), v_role)
  on conflict (collection_id, user_id) do update set role = excluded.role;

  update public.collection_invites set accepted_at = now() where id = p_invite_id;
end;
$$;

grant execute on function public.accept_collection_invite(bigint) to authenticated;

-- Owner is auto-added as a member with role 'owner' when a collection is created.
create or replace function public.add_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.collection_members (collection_id, user_id, role)
  values (new.id, new.owner_id, 'owner');
  return new;
end;
$$;

create trigger cloud_collections_add_owner
after insert on public.cloud_collections
for each row execute function public.add_owner_as_member();

-- Enable Realtime so all members see live changes.
alter publication supabase_realtime add table public.cloud_collections;
alter publication supabase_realtime add table public.collection_members;
alter publication supabase_realtime add table public.cloud_folders;
alter publication supabase_realtime add table public.cloud_requests;

-- The client streams these two tables filtered by collection_id. With the
-- default replica identity a DELETE event's old row carries only the primary
-- key, so that filter never matches and deletes (including FK cascades) never
-- reach any client. `full` puts every column in the old row.
alter table public.cloud_folders replica identity full;
alter table public.cloud_requests replica identity full;
