'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'

export interface FeaturedArticlePayload {
  title: string
  url: string
  snippet?: string | null
  source?: string | null
  image_url?: string | null
  published_at?: string | null
}

export async function addFeaturedArticle(payload: FeaturedArticlePayload) {
  const db = createAdminClient()
  const { data: maxRow } = await db
    .from('featured_articles')
    .select('sort_order')
    .order('sort_order', { ascending: false })
    .limit(1)
    .maybeSingle()
  const nextOrder = (maxRow?.sort_order ?? -1) + 1
  const { error } = await db.from('featured_articles').insert({
    ...payload,
    sort_order: nextOrder,
    active: true,
  })
  if (error) throw new Error(`addFeaturedArticle: ${error.message}`)
  revalidatePath('/dashboard/featured')
}

export async function updateFeaturedArticle(id: string, payload: Partial<FeaturedArticlePayload>) {
  const db = createAdminClient()
  const { error } = await db
    .from('featured_articles')
    .update({ ...payload, updated_at: new Date().toISOString() })
    .eq('id', id)
  if (error) throw new Error(`updateFeaturedArticle: ${error.message}`)
  revalidatePath('/dashboard/featured')
}

export async function deleteFeaturedArticle(id: string) {
  const db = createAdminClient()
  const { error } = await db.from('featured_articles').delete().eq('id', id)
  if (error) throw new Error(`deleteFeaturedArticle: ${error.message}`)
  revalidatePath('/dashboard/featured')
}

export async function toggleFeaturedActive(id: string, active: boolean) {
  const db = createAdminClient()
  const { error } = await db
    .from('featured_articles')
    .update({ active, updated_at: new Date().toISOString() })
    .eq('id', id)
  if (error) throw new Error(`toggleFeaturedActive: ${error.message}`)
  revalidatePath('/dashboard/featured')
}

export async function moveFeaturedArticle(id: string, direction: 'up' | 'down') {
  const db = createAdminClient()
  const { data: all } = await db
    .from('featured_articles')
    .select('id, sort_order')
    .order('sort_order', { ascending: true })
  if (!all) return
  const idx = all.findIndex((r) => r.id === id)
  const swapIdx = direction === 'up' ? idx - 1 : idx + 1
  if (swapIdx < 0 || swapIdx >= all.length) return
  const a = all[idx], b = all[swapIdx]
  await Promise.all([
    db.from('featured_articles').update({ sort_order: b.sort_order }).eq('id', a.id),
    db.from('featured_articles').update({ sort_order: a.sort_order }).eq('id', b.id),
  ])
  revalidatePath('/dashboard/featured')
}
