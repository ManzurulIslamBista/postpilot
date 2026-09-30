-- Fix: deleting a folder or request succeeded in the database but never
-- disappeared from any client's tree. The app streams cloud_folders and
-- cloud_requests filtered by collection_id, and with the default replica
-- identity a Realtime DELETE event's old row carries only the primary key, so
-- that filter never matches. Run once in the Supabase SQL Editor (safe to
-- re-run).
alter table public.cloud_folders replica identity full;
alter table public.cloud_requests replica identity full;
