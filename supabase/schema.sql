-- Run this in Supabase SQL Editor
create table if not exists links (
  id          uuid primary key default gen_random_uuid(),
  url         text not null unique,          -- unique = auto-dedupe on re-save
  title       text,
  description text,
  image       text,
  collection  text not null default 'Inbox',
  status      text not null default 'pending', -- pending -> ready
  -- curation state, edited from the map page (index.html):
  board       text not null default 'backlog', -- 'backlog' (Unread) | 'inspiration'
  pos         jsonb,                            -- { x, y, detached } once dragged / cut
  consumed    boolean not null default false,   -- read / done → hidden from both boards
  created_at  timestamptz not null default now()
);

alter table links enable row level security;

-- The map reads with the anon key…
create policy "public read" on links for select using (true);

-- …and may curate + re-file categories, but ONLY these columns. url/title/
-- image stay writable server-side only (via the save edge function).
create policy "anon curate" on links for update to anon using (true) with check (true);
revoke update on links from anon;
grant  update (board, pos, consumed, collection) on links to anon;

-- Categories are first-class rows, editable from the map's sidebar
-- (double-click to rename, + to add, × to delete → its links move to Inbox).
create table if not exists collections (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,
  position   int  not null default 0,             -- sidebar order (drag to reorder)
  pos        jsonb,                                -- { backlog:{x,y}, inspiration:{x,y} } once a bubble is dragged
  created_at timestamptz not null default now()
);
alter table collections enable row level security;
create policy "public read collections"   on collections for select using (true);
create policy "anon manage collections"    on collections for all to anon using (true) with check (true);
grant select, insert, update, delete on collections to anon;
