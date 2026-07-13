// Server-only AV-track logic shared by the upload route handler and the
// dashboard server actions. Uploads travel through a Route Handler (not a
// Server Action) because multi-file multipart bodies hit "Unexpected end of
// form" in the server-action parser; request.formData() in a route handler is
// the documented-safe path for file uploads.

import { createAdminClient } from '@/lib/supabase/server'

export const AV_BUCKET = 'av-tracks'

export const SLOT_KEYS = ['original', 'vocals', 'drums', 'bass', 'other'] as const
export type SlotKey = (typeof SLOT_KEYS)[number]

// `original` keeps the exporter's `master` filename on disk
const SLOT_BASENAME: Record<SlotKey, string> = {
  original: 'master',
  vocals: 'vocals',
  drums: 'drums',
  bass: 'bass',
  other: 'other',
}

const AUDIO_CONTENT_TYPES: Record<string, string> = {
  mp3: 'audio/mpeg',
  m4a: 'audio/mp4',
  wav: 'audio/wav',
}

export interface TrackManifest {
  version: number
  title: string
  crop: { start: number; duration: number }
  files: Record<string, string>
  settings: { engine: Record<string, unknown>; look: Record<string, unknown> }
}

export interface AvTrackRow {
  id: string
  title: string
  artist: string | null
  position: number
  crop_start_s: number
  duration_s: number
  files: Record<string, string>
  settings: TrackManifest['settings']
  chart_path: string | null
  created_at: string
}

/**
 * Create a track from the lab bundle. FormData contract (see av-tracks-client):
 *   manifest        track.json content (string)
 *   artist          optional artist name
 *   audio_<slot>    one File per slot present in the bundle
 *   chart           optional chart.json File
 */
export async function createAvTrackFromForm(formData: FormData): Promise<string> {
  const manifestRaw = formData.get('manifest')
  if (typeof manifestRaw !== 'string' || !manifestRaw) throw new Error('No manifest provided')

  let manifest: TrackManifest
  try {
    manifest = JSON.parse(manifestRaw)
  } catch {
    throw new Error('track.json is not valid JSON')
  }
  if (manifest.version !== 1) throw new Error(`Unsupported track.json version: ${manifest.version}`)
  if (!manifest.settings || !manifest.crop) throw new Error('track.json missing settings/crop')

  const uploads: Array<{ slot: SlotKey; file: File }> = []
  for (const slot of SLOT_KEYS) {
    const file = formData.get(`audio_${slot}`)
    if (file instanceof File && file.size > 0) uploads.push({ slot, file })
  }
  if (!uploads.some((u) => u.slot === 'original')) {
    throw new Error('Bundle must include the original (master) audio — it is the only audible file')
  }

  const db = createAdminClient()

  const artist = typeof formData.get('artist') === 'string' ? String(formData.get('artist')).trim() || null : null

  const { data: maxRow } = await db
    .from('av_tracks')
    .select('position')
    .order('position', { ascending: false })
    .limit(1)
    .maybeSingle()
  const position = (maxRow?.position ?? -1) + 1

  const { data: created, error: insertError } = await db
    .from('av_tracks')
    .insert({
      title: manifest.title || 'Untitled',
      artist,
      position,
      crop_start_s: manifest.crop.start,
      duration_s: manifest.crop.duration,
      files: {},
      settings: manifest.settings,
    })
    .select('id')
    .single()
  if (insertError) throw new Error(`Insert failed: ${insertError.message}`)
  const id = created.id as string

  const files: Record<string, string> = {}
  for (const { slot, file } of uploads) {
    const ext = (file.name.split('.').pop() ?? 'mp3').toLowerCase()
    const contentType = AUDIO_CONTENT_TYPES[ext]
    if (!contentType) throw new Error(`Unsupported audio type .${ext} for ${slot} (use mp3, m4a, or wav)`)
    const path = `${id}/${SLOT_BASENAME[slot]}.${ext}`
    const { error } = await db.storage.from(AV_BUCKET).upload(path, file, { upsert: true, contentType })
    if (error) {
      // roll the row back so a half-uploaded track never reaches the playlist
      await db.from('av_tracks').delete().eq('id', id)
      throw new Error(`Upload failed for ${slot}: ${error.message}`)
    }
    files[slot] = path
  }

  // Optional precomputed reactivity chart (chart.json from the lab export).
  // NOT added to `files`: that map is audio-only (it feeds the playlist
  // loader's decode loop). deleteAvTrack removes the chart via chart_path.
  let chartPath: string | null = null
  const chartFile = formData.get('chart')
  if (chartFile instanceof File && chartFile.size > 0) {
    chartPath = `${id}/chart.json`
    const { error } = await db.storage
      .from(AV_BUCKET)
      .upload(chartPath, chartFile, { upsert: true, contentType: 'application/json' })
    if (error) {
      await db.from('av_tracks').delete().eq('id', id)
      throw new Error(`Chart upload failed: ${error.message}`)
    }
  }

  const { error: updateError } = await db
    .from('av_tracks')
    .update({ files, chart_path: chartPath })
    .eq('id', id)
  if (updateError) throw new Error(`Files update failed: ${updateError.message}`)

  await regeneratePlaylistManifest(db)
  return id
}

/**
 * Rebuild the bucket-root playlist.json the visualizer fetches. Absolute
 * public URLs so the page needs zero Supabase config beyond the manifest URL.
 */
export async function regeneratePlaylistManifest(db: ReturnType<typeof createAdminClient>): Promise<void> {
  const { data: rows, error } = await db
    .from('av_tracks')
    .select('id, title, artist, position, crop_start_s, duration_s, files, settings, chart_path')
    .order('position', { ascending: true })
  if (error) throw new Error(`Manifest query failed: ${error.message}`)

  const toPublicUrl = (path: string) => db.storage.from(AV_BUCKET).getPublicUrl(path).data.publicUrl

  const manifest = {
    version: 1,
    generatedAt: new Date().toISOString(),
    tracks: (rows ?? []).map((r) => ({
      id: r.id,
      title: r.title,
      artist: r.artist,
      crop: { start: Number(r.crop_start_s), duration: Number(r.duration_s) },
      files: Object.fromEntries(
        Object.entries((r.files ?? {}) as Record<string, string>).map(([slot, path]) => [slot, toPublicUrl(path)]),
      ),
      settings: r.settings,
      chartUrl: r.chart_path ? toPublicUrl(r.chart_path) : null,
    })),
  }

  // cacheControl 60s: reorder/delete propagates within a minute; the page also
  // adds a cache-buster query param on fetch.
  const { error: uploadError } = await db.storage
    .from(AV_BUCKET)
    .upload('playlist.json', new Blob([JSON.stringify(manifest, null, 2)], { type: 'application/json' }), {
      upsert: true,
      contentType: 'application/json',
      cacheControl: '60',
    })
  if (uploadError) throw new Error(`Manifest upload failed: ${uploadError.message}`)
}
