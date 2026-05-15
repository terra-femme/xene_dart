# Xene

A music discovery feed that aggregates releases, mixes, and uploads from artists you follow across SoundCloud, Bandcamp, YouTube, and Beatport — unified in a single scrolling feed.

## Architecture

Three packages under a Dart workspace:

| Package | Role |
|---|---|
| `packages/xene_domain` | Shared models (`FeedItem`, `Artist`) and identity engine |
| `packages/xene_backend` | Dart Frog API server — feed aggregation, caching, background sync |
| `packages/xene_app` | Flutter PWA — feed UI, preset dial, audio player |

### Backend

- **Feed aggregation** — `/feed/merged` fetches SoundCloud, Bandcamp, YouTube, and Beatport concurrently. SC/YT run at concurrency=12; Bandcamp scrapes run serially to avoid 429s.
- **Two-tier cache** — `last_polled` TTL check (Supabase `system_cache`) → `feed_items` DB rows → live fetch. Stale rows are served immediately while a background refresh runs.
- **Presets** — `/presets` endpoint serves dial configuration. Each preset maps to a curated artist list (`preset_template_sources`). `/feed/merged?preset_id=slug` scopes the feed to that artist set.
- **Scheduler** — cron jobs refresh SoundCloud (every 8h), Bandcamp (every 6h), YouTube (every 12h), Beatport (daily), and press articles (twice daily).
- **Search** — `/feed/merged?q=term` bypasses the carousel and runs a cross-column `ilike` search over the full 31-day `feed_items` cache.
- **Additional routes** — artist CRUD, SC OAuth, SoundCloud stream proxy, image CORS proxy, AI-powered discovery graph, press scout.

### Frontend

- **Preset dial** — rotary knob that switches between curated artist presets. Ticks snap to named notches; haptic feedback on mobile.
- **Feed lanes** — 7-day "recent" lane (phase 1: SC+YT fast, phase 2: Bandcamp concurrent) + archive sheet (8–31 days, lazy-loaded on open).
- **Feed cards** — thumbnail, content-type pill, platform badge, pre-order star for future-dated releases, teal highlight for first-seen items.
- **Draggable sheet** — swipe-up archive with paginated carousel rotation and full-greed mode.
- **Audio player** — SoundCloud oEmbed, YouTube embed, Bandcamp embed. Persists across navigation.
- **Search** — inline text field in the control bar; queries the full 31-day cache via backend `ilike`.

### Data flow

```
Flutter app
  └─ GET /feed/merged?preset_id=dnb-foundations&zone=recent&platforms=soundcloud,youtube
       └─ getArtistsForPreset()  →  preset_template_sources + artists (Supabase)
       └─ fetchWithCache() × N artists  →  last_polled TTL gate  →  feed_items DB
            └─ cache miss / stale  →  SoundCloudService / YouTubeService / BandcampService
                                         └─ live fetch  →  saveFeedItems()  →  setLastPolled()
       └─ merge + dedup + zone filter + exposure tracking
       └─ JSON response  →  FeedItem.fromJson()  →  filteredFeedProvider  →  XeneFeedCard
```

## Setup

### Requirements

- Dart SDK `^3.11.5` / Flutter SDK `^3.x`
- Supabase project (Postgres + service key)
- Platform credentials (see Environment Variables below)

### Install

```bash
# From the repo root — resolves all three packages via Dart workspace
dart pub get
```

### Environment variables

Create `packages/xene_backend/.env`:

```
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
TOKEN_ENCRYPTION_KEY=your-32-byte-base64-key

SC_CLIENT_ID=soundcloud-client-id
SC_CLIENT_SECRET=soundcloud-client-secret

YOUTUBE_API_KEY=your-yt-data-v3-key

BEATPORT_USERNAME=your-email
BEATPORT_PASSWORD=your-password

TWITCH_CLIENT_ID=twitch-app-id
TWITCH_CLIENT_SECRET=twitch-app-secret

FRONTEND_URL=http://localhost:5555
GEMINI_API_KEY=your-gemini-key        # optional, powers discovery graph
```

### Run

**Backend** (defaults to `localhost:8080`):

```bash
cd packages/xene_backend
dart_frog dev
```

**App** (web, defaults to `localhost:5555`):

```bash
cd packages/xene_app
flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:8080
```

For a production build:

```bash
flutter build web --dart-define=BACKEND_URL=https://your-backend.run.app
```

## Supabase tables

| Table | Purpose |
|---|---|
| `artists` | Global artist registry with per-platform identifiers |
| `user_artist_follows` | Which artists a user follows |
| `preset_templates` | Named presets with dial metadata (slug, color, notch_index) |
| `preset_template_sources` | Artist membership in each preset |
| `user_custom_preset_sources` | Per-user custom notch overrides |
| `user_preset_selection` | Last active preset per user |
| `feed_items` | Cached content (31-day rolling window) |
| `system_cache` | TTL key-value store (`last_polled`, empty-window markers, exposure IDs) |
| `youtube_channel_cache` | YouTube URL → channel ID resolution cache |
| `artist_articles` | Press articles sourced by the press scout service |
