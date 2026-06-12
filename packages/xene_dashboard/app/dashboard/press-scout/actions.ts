'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export async function deleteArtistArticle(id: string): Promise<void> {
  const db = createAdminClient()
  const { error } = await db.from('artist_articles').delete().eq('id', id)
  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/press-scout')
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
