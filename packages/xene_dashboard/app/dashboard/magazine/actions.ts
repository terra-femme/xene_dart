'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import type { MagazineHotspot, MagazineMotionLayer } from '@/lib/types/database'

interface CoverPayload {
  title: string
  dek: string | null
  aspect_ratio: string
  background_image_url: string
  fallback_image_url: string | null
  alt_text: string | null
  hotspots: MagazineHotspot[]
  motion_layers: MagazineMotionLayer[]
}

export async function saveCover(id: string, payload: CoverPayload) {
  const db = createAdminClient()
  const { error } = await db
    .from('magazine_covers')
    .update(payload)
    .eq('id', id)

  if (error) throw new Error(`saveCover failed: ${error.message}`)
  revalidatePath('/dashboard/magazine')
  revalidatePath(`/dashboard/magazine/${id}`)
}

export async function createCover(payload: Omit<CoverPayload, 'hotspots' | 'motion_layers'>) {
  const db = createAdminClient()
  const { data, error } = await db
    .from('magazine_covers')
    .insert({ ...payload, hotspots: [], motion_layers: [], active: false })
    .select('id')
    .single()

  if (error) throw new Error(`createCover failed: ${error.message}`)
  revalidatePath('/dashboard/magazine')
  return data.id as string
}

export async function deleteCover(id: string) {
  const db = createAdminClient()
  const { error } = await db.from('magazine_covers').delete().eq('id', id)
  if (error) throw new Error(`deleteCover failed: ${error.message}`)
  revalidatePath('/dashboard/magazine')
}

export async function activateCover(id: string) {
  const db = createAdminClient()
  // Clear existing active cover first (partial unique index requires this order)
  await db.from('magazine_covers').update({ active: false }).eq('active', true)
  const { error } = await db
    .from('magazine_covers')
    .update({ active: true })
    .eq('id', id)
  if (error) throw new Error(`activateCover failed: ${error.message}`)
  revalidatePath('/dashboard/magazine')
}

export async function deactivateCover(id: string) {
  const db = createAdminClient()
  const { error } = await db
    .from('magazine_covers')
    .update({ active: false })
    .eq('id', id)
  if (error) throw new Error(`deactivateCover failed: ${error.message}`)
  revalidatePath('/dashboard/magazine')
}

export async function uploadMotionLayerFile(formData: FormData): Promise<string> {
  const file = formData.get('file') as File
  if (!file) throw new Error('No file provided')

  const db = createAdminClient()
  const ext = file.name.split('.').pop() ?? 'lottie'
  const path = `lottie/${Date.now()}-${Math.random().toString(36).slice(2, 6)}.${ext}`

  // dotLottie (.lottie) is a zip container — no registered MIME type, use octet-stream
  const contentType = ext === 'json' ? 'application/json' : 'application/octet-stream'

  const { error } = await db.storage
    .from('covers')
    .upload(path, file, { upsert: false, contentType })

  if (error) throw new Error(`Upload failed: ${error.message}`)

  const { data } = db.storage.from('covers').getPublicUrl(path)
  return data.publicUrl
}

export async function uploadCoverImage(formData: FormData): Promise<string> {
  const file = formData.get('file') as File
  if (!file) throw new Error('No file provided')

  const db = createAdminClient()
  const ext = file.name.split('.').pop() ?? 'webp'
  const path = `covers/${Date.now()}.${ext}`

  const { error } = await db.storage
    .from('covers')
    .upload(path, file, { upsert: true, contentType: file.type })

  if (error) throw new Error(`Upload failed: ${error.message}`)

  const { data } = db.storage.from('covers').getPublicUrl(path)
  return data.publicUrl
}
