-- AV visualizer playlist: producer-curated 30s track bundles.
--
-- Storage: bucket `av-tracks` (public read) holds, per track:
--   {track_id}/master.mp3          audible 30s crop of the original mix
--   {track_id}/<stem>.mp3          silent analysis stems (vocals/drums/bass/other)
-- plus one bucket-root `playlist.json` manifest that the visualizer page
-- fetches directly (no auth, no PostgREST — the WebView page has no session).
--
-- Writes go through the xene_dashboard admin pages (service role, bypasses
-- RLS); anon/authenticated clients are read-only by design.

create table if not exists public.av_tracks (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  artist text,
  position integer not null default 0,
  crop_start_s numeric not null default 0,
  duration_s numeric not null default 30,
  files jsonb not null default '{}'::jsonb,
  settings jsonb not null default '{}'::jsonb,
  chart_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.av_tracks is
  'AV visualizer playlist: 30s crops + reactivity settings. files = slot key -> storage path in av-tracks bucket.';
comment on column public.av_tracks.chart_path is
  'Precomputed reactivity chart JSON path (Phase 4). NULL = engine falls back to live DSP on the stems.';

alter table public.av_tracks enable row level security;

drop policy if exists "av_tracks_public_read" on public.av_tracks;
create policy "av_tracks_public_read"
  on public.av_tracks for select
  using (true);
-- No insert/update/delete policies on purpose: only the dashboard's service
-- role writes, and service role bypasses RLS.

-- Public bucket for the audio + manifest. public = true serves objects at
-- /storage/v1/object/public/av-tracks/... without any policy or token.
insert into storage.buckets (id, name, public)
values ('av-tracks', 'av-tracks', true)
on conflict (id) do nothing;
