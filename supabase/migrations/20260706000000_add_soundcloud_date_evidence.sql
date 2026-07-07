alter table public.feed_items
  add column if not exists source_created_at timestamptz,
  add column if not exists source_display_at timestamptz,
  add column if not exists source_release_at timestamptz,
  add column if not exists source_last_modified_at timestamptz,
  add column if not exists date_source text,
  add column if not exists date_confidence text,
  add column if not exists date_conflict_reason text,
  add column if not exists is_upcoming boolean not null default false;

create index if not exists idx_feed_items_soundcloud_release_at
  on public.feed_items (source_release_at)
  where platform = 'soundcloud' and is_upcoming = true;
