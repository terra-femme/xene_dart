'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export interface PollResponse {
  status: string
  preset?: string
  message: string
  error?: string
}

export async function deleteArtistArticle(id: string): Promise<void> {
  const db = createAdminClient()
  const { error } = await db.from('artist_articles').delete().eq('id', id)
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/press-scout')
}

export async function triggerPublicationPolling(
  token: string,
  backendUrl: string,
  presetSlug?: string,
): Promise<PollResponse> {
  const url = new URL(`${backendUrl}/press-scout/poll-publications`)
  if (presetSlug) {
    url.searchParams.set('preset_id', presetSlug)
  }

  const res = await fetch(url.toString(), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
  })

  if (!res.ok) {
    const body = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error((body as { error?: string }).error ?? `HTTP ${res.status}`)
  }

  return await res.json()
}

interface UpdateArticlePayload {
  title: string
  url: string
  snippet: string
  source: string
}

export async function updateArtistArticle(
  id: string,
  payload: UpdateArticlePayload,
): Promise<void> {
  const db = createAdminClient()
  const { error } = await db
    .from('artist_articles')
    .update({
      title: payload.title,
      url: payload.url,
      snippet: payload.snippet || null,
      source: payload.source || null,
    })
    .eq('id', id)
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/press-scout')
}
