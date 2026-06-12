export interface MagazineHotspot {
  id: string
  x: number
  y: number
  width: number
  height: number
  title: string
  body: string | null
  article_url: string | null
}

export interface MagazineMotionLayer {
  id: string
  type: string
  url: string
  x: number
  y: number
  width: number
  height: number
  loop: boolean
  opacity: number   // 0.0–1.0, default 1
  speed: number     // playback rate multiplier, default 1.0
}

export interface MagazineCover {
  id: string
  title: string
  dek: string | null
  aspect_ratio: string
  background_image_url: string
  fallback_image_url: string | null
  alt_text: string | null
  published_at: string
  active: boolean
  motion_layers: MagazineMotionLayer[]
  hotspots: MagazineHotspot[]
  created_at: string
}

export interface PresetTemplate {
  id: string
  slug: string
  name: string
  description: string | null
  notch_index: number
  theme_color: string
  is_default: boolean
  is_public: boolean
  enabled: boolean
  version: number
  created_at: string
  updated_at: string
}

export interface PresetTemplateSource {
  id: string
  template_id: string
  artist_id: string | null
  platform: string
  display_name: string
  soundcloud_username: string | null
  soundcloud_url: string | null
  bandcamp_url: string | null
  youtube_channel_id: string | null
  youtube_url: string | null
  enabled: boolean
  metadata: Record<string, unknown> | null
  created_at: string
  updated_at: string
}

export interface Artist {
  id: string
  name: string
  entity_type: string
  manually_verified: boolean
  soundcloud_username: string | null
  soundcloud_url: string | null
  soundcloud_authority: string | null
  youtube_channel_id: string | null
  youtube_url: string | null
  youtube_authority: string | null
  spotify_id: string | null
  spotify_url: string | null
  bandcamp_url: string | null
  bandcamp_authority: string | null
  instagram_username: string | null
  twitter_username: string | null
  twitch_login: string | null
  website_url: string | null
  genre_tags: string[]
  aliases: string[]
  identity_confidence: string | null
  coverage_level: string | null
  conflict_state: boolean
  last_press_scout_at: string | null
  created_at: string
  updated_at: string
}

export interface Profile {
  id: string
  email: string | null
  role: string
  username: string | null
  username_updated_at: string | null
  created_at: string
  updated_at: string
}

export interface PressPublication {
  id: string
  name: string
  slug: string
  url: string | null
  rss_url: string | null
  logo_url: string | null
  genres: string[]
  tier: number
  region: string | null
  enabled: boolean
  last_polled: string | null
  last_status: number | null
  failure_count: number
  last_error: string | null
  next_poll_at: string | null
  created_at: string
  updated_at: string
}

export interface ArtistArticle {
  id: string
  artist_id: string
  artist_name: string | null
  title: string
  url: string
  snippet: string | null
  source: string | null
  published_at: string | null
  discovered_at: string
  preset_slug: string | null
}

export interface GameParty {
  id: string
  name: string
  created_by: string
  invite_code: string
  created_at: string
  is_active: boolean
}

export interface PartyTrack {
  id: string
  party_id: string
  user_id: string
  sc_track_id: string
  sc_track_url: string
  sc_title: string
  sc_artwork_url: string | null
  sc_duration_seconds: number | null
  week_start: string
  submitted_at: string
}

export interface PartyScore {
  id: string
  party_id: string
  user_id: string
  total_score: number
  updated_at: string
}

// ─── Social Analytics ─────────────────────────────────────────────────────────

export type SocialPlatform = 'youtube' | 'soundcloud' | 'twitch' | 'instagram' | 'tiktok'

export interface ConnectedAccount {
  id: string
  org_id: string
  platform: SocialPlatform
  account_id: string | null
  username: string | null
  connected_at: string
}

export interface SocialMetric {
  id: string
  org_id: string
  platform: SocialPlatform
  metric_date: string
  followers: number | null
  total_views: number | null
  total_likes: number | null
  posts_count: number | null
  metadata: Record<string, unknown>
  created_at: string
}

// ─── Xene Articles ────────────────────────────────────────────────────────────

export type ArticleStatus = 'draft' | 'published' | 'scheduled'
export type LayoutTemplate = 'editorial' | 'interview' | 'visual_essay' | 'audio_story' | 'custom'
export type BlockType = 'text' | 'quote' | 'image' | 'video' | 'voice_note' | 'spacer'
export type SpacerSize = 'sm' | 'md' | 'lg'
export type VideoProvider = 'youtube' | 'direct'
export type ImageAspect = '16:9' | '4:3' | '1:1' | '3:4'

export interface TextBlock {
  id: string
  type: 'text'
  heading: string | null
  body: string
}

export interface QuoteBlock {
  id: string
  type: 'quote'
  text: string
  attribution: string | null
}

export interface ImageBlock {
  id: string
  type: 'image'
  url: string
  caption: string | null
  aspect: ImageAspect
}

export interface VideoBlock {
  id: string
  type: 'video'
  url: string
  thumbnail_url: string | null
  provider: VideoProvider
}

export interface VoiceNoteBlock {
  id: string
  type: 'voice_note'
  url: string
  duration_seconds: number | null
  transcript: string | null
}

export interface SpacerBlock {
  id: string
  type: 'spacer'
  size: SpacerSize
}

export type ArticleBlock =
  | TextBlock
  | QuoteBlock
  | ImageBlock
  | VideoBlock
  | VoiceNoteBlock
  | SpacerBlock

export interface XeneArticle {
  id: string
  slug: string
  title: string
  dek: string | null
  author: string | null
  layout_template: LayoutTemplate
  section_label: string | null
  status: ArticleStatus
  cover_image_url: string | null
  theme_color: string | null
  blocks: ArticleBlock[]
  published_at: string | null
  scheduled_for: string | null
  created_at: string
  updated_at: string
}
