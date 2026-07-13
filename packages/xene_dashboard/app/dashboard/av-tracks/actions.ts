'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import { AV_BUCKET, regeneratePlaylistManifest } from '@/lib/av-tracks'

// AV playlist admin actions: delete + reorder. Track CREATION goes through
// the route handler at app/api/av-tracks/upload (multi-file multipart bodies
// break the server-action parser — see lib/av-tracks.ts). Every mutation here
// regenerates the bucket-root playlist.json the visualizer consumes.

export async function deleteAvTrack(id: string): Promise<void> {
  const db = createAdminClient()

  const { data: row, error: fetchError } = await db
    .from('av_tracks')
    .select('files, chart_path')
    .eq('id', id)
    .single()
  if (fetchError) throw new Error(`Track not found: ${fetchError.message}`)

  const paths = Object.values((row.files ?? {}) as Record<string, string>)
  if (row.chart_path) paths.push(row.chart_path)
  if (paths.length > 0) {
    const { error } = await db.storage.from(AV_BUCKET).remove(paths)
    if (error) throw new Error(`Storage delete failed: ${error.message}`)
  }

  const { error } = await db.from('av_tracks').delete().eq('id', id)
  if (error) throw new Error(`Delete failed: ${error.message}`)

  await regeneratePlaylistManifest(db)
  revalidatePath('/dashboard/av-tracks')
}

/** Swap positions with the neighbouring track (direction -1 = up, +1 = down). */
export async function moveAvTrack(id: string, direction: -1 | 1): Promise<void> {
  const db = createAdminClient()

  const { data: rows, error } = await db
    .from('av_tracks')
    .select('id, position')
    .order('position', { ascending: true })
  if (error) throw new Error(`Reorder fetch failed: ${error.message}`)

  const idx = (rows ?? []).findIndex((r) => r.id === id)
  const other = idx >= 0 ? rows![idx + direction] : undefined
  if (!other) return // already at the edge

  const current = rows![idx]
  const updates = [
    db.from('av_tracks').update({ position: other.position }).eq('id', current.id),
    db.from('av_tracks').update({ position: current.position }).eq('id', other.id),
  ]
  for (const u of updates) {
    const { error: swapError } = await u
    if (swapError) throw new Error(`Reorder failed: ${swapError.message}`)
  }

  await regeneratePlaylistManifest(db)
  revalidatePath('/dashboard/av-tracks')
}
