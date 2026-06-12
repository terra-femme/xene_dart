'use server'

import { createAdminClient } from '@/lib/supabase/server'

interface MetricSnapshot {
  platform: string
  followers: number | null
  total_views: number | null
  total_likes: number | null
  posts_count: number | null
  metadata: Record<string, unknown>
}

async function fetchYouTubeMetrics(): Promise<MetricSnapshot | null> {
  const apiKey = process.env.YOUTUBE_API_KEY
  const channelId = process.env.XENE_YOUTUBE_CHANNEL_ID

  if (!apiKey || !channelId) {
    console.warn('[social/actions] fetchYouTubeMetrics: missing YOUTUBE_API_KEY or XENE_YOUTUBE_CHANNEL_ID — skipping')
    return null
  }

  console.log('[social/actions] fetchYouTubeMetrics: fetching channel stats', { channelId })

  const res = await fetch(
    `https://www.googleapis.com/youtube/v3/channels?part=statistics&id=${channelId}&key=${apiKey}`,
    { cache: 'no-store' },
  )

  if (!res.ok) {
    const body = await res.text()
    console.error('[social/actions] fetchYouTubeMetrics: API error', res.status, body.slice(0, 300))
    return null
  }

  const data = await res.json()
  const stats = data.items?.[0]?.statistics

  if (!stats) {
    console.warn('[social/actions] fetchYouTubeMetrics: no statistics block returned')
    return null
  }

  console.log('[social/actions] fetchYouTubeMetrics: ok', {
    subscribers: stats.subscriberCount,
    views: stats.viewCount,
    videos: stats.videoCount,
  })

  return {
    platform: 'youtube',
    followers: stats.hiddenSubscriberCount ? null : parseInt(stats.subscriberCount ?? '0'),
    total_views: parseInt(stats.viewCount ?? '0'),
    total_likes: null,
    posts_count: parseInt(stats.videoCount ?? '0'),
    metadata: { hidden_subscriber_count: stats.hiddenSubscriberCount ?? false },
  }
}

async function getSoundCloudToken(): Promise<string | null> {
  const clientId = process.env.SC_CLIENT_ID
  const clientSecret = process.env.SC_CLIENT_SECRET

  if (!clientId || !clientSecret) {
    console.warn('[social/actions] getSoundCloudToken: missing SC_CLIENT_ID or SC_CLIENT_SECRET')
    return null
  }

  console.log('[social/actions] getSoundCloudToken: requesting client credentials token')

  const res = await fetch('https://secure.soundcloud.com/oauth/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: clientId,
      client_secret: clientSecret,
    }),
    cache: 'no-store',
  })

  if (!res.ok) {
    console.error('[social/actions] getSoundCloudToken: error', res.status, await res.text())
    return null
  }

  const data = await res.json()
  console.log('[social/actions] getSoundCloudToken: token received')
  return data.access_token ?? null
}

async function fetchSoundCloudMetrics(): Promise<MetricSnapshot | null> {
  const username = process.env.XENE_SOUNDCLOUD_USERNAME

  if (!username) {
    console.warn('[social/actions] fetchSoundCloudMetrics: missing XENE_SOUNDCLOUD_USERNAME — skipping')
    return null
  }

  const token = await getSoundCloudToken()
  if (!token) return null

  console.log('[social/actions] fetchSoundCloudMetrics: fetching user profile', { username })

  const userRes = await fetch(`https://api.soundcloud.com/users/${username}`, {
    headers: { Authorization: `OAuth ${token}` },
    cache: 'no-store',
  })

  if (!userRes.ok) {
    const body = await userRes.text()
    console.error('[social/actions] fetchSoundCloudMetrics: user fetch error', userRes.status, body.slice(0, 300))
    return null
  }

  const user = await userRes.json()
  console.log('[social/actions] fetchSoundCloudMetrics: user ok', {
    followers: user.followers_count,
    tracks: user.track_count,
  })

  // Aggregate play + like counts across up to 50 public tracks
  let totalPlays = 0
  let totalLikes = 0

  const tracksRes = await fetch(
    `https://api.soundcloud.com/users/${username}/tracks?limit=50`,
    { headers: { Authorization: `OAuth ${token}` }, cache: 'no-store' },
  )

  if (tracksRes.ok) {
    const tracks = await tracksRes.json()
    for (const t of tracks) {
      totalPlays += t.playback_count ?? 0
      totalLikes += t.likes_count ?? 0
    }
    console.log(`[social/actions] fetchSoundCloudMetrics: ${tracks.length} tracks — plays=${totalPlays} likes=${totalLikes}`)
  } else {
    console.warn('[social/actions] fetchSoundCloudMetrics: tracks fetch failed', tracksRes.status)
  }

  return {
    platform: 'soundcloud',
    followers: user.followers_count ?? null,
    total_views: totalPlays,
    total_likes: totalLikes,
    posts_count: user.track_count ?? null,
    metadata: { permalink_url: user.permalink_url ?? null },
  }
}

export async function refreshMetrics(): Promise<{ ok: boolean; message: string }> {
  console.log('[social/actions] refreshMetrics: starting')

  const [ytSnapshot, scSnapshot] = await Promise.all([
    fetchYouTubeMetrics(),
    fetchSoundCloudMetrics(),
  ])

  const valid = [ytSnapshot, scSnapshot].filter(Boolean) as MetricSnapshot[]

  if (valid.length === 0) {
    console.warn('[social/actions] refreshMetrics: no snapshots fetched — check env vars')
    return { ok: false, message: 'No metrics fetched — check env vars (YOUTUBE_API_KEY, XENE_YOUTUBE_CHANNEL_ID, SC_CLIENT_ID, SC_CLIENT_SECRET, XENE_SOUNDCLOUD_USERNAME).' }
  }

  const today = new Date().toISOString().split('T')[0]
  console.log(`[social/actions] refreshMetrics: upserting ${valid.length} snapshots for ${today}`)

  const db = createAdminClient()
  const { error } = await db.from('social_metrics').upsert(
    valid.map((s) => ({
      org_id: 'xene',
      platform: s.platform,
      metric_date: today,
      followers: s.followers,
      total_views: s.total_views,
      total_likes: s.total_likes,
      posts_count: s.posts_count,
      metadata: s.metadata,
    })),
    { onConflict: 'org_id,platform,metric_date' },
  )

  if (error) {
    console.error('[social/actions] refreshMetrics: upsert error', error)
    return { ok: false, message: error.message }
  }

  console.log(`[social/actions] refreshMetrics: done — ${valid.map((s) => s.platform).join(', ')}`)
  return { ok: true, message: `Updated: ${valid.map((s) => s.platform).join(', ')}` }
}
