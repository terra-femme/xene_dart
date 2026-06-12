'use server'

import { createAdminClient } from '@/lib/supabase/server'
import { revalidatePath } from 'next/cache'
import type { ArticleBlock, LayoutTemplate, ArticleStatus } from '@/lib/types/database'

interface CreateArticlePayload {
  title: string
  slug: string
  layout_template: LayoutTemplate
  dek: string | null
  author: string | null
  cover_image_url: string | null
  theme_color: string | null
}

export async function createArticle(payload: CreateArticlePayload): Promise<string> {
  const db = createAdminClient()
  const { data, error } = await db
    .from('xene_articles')
    .insert({ ...payload, blocks: [] })
    .select('id')
    .single()

  if (error) throw new Error(error.message)
  return data.id
}

interface SaveArticlePayload {
  title: string
  slug: string
  dek: string | null
  author: string | null
  layout_template: LayoutTemplate
  section_label: string | null
  cover_image_url: string | null
  theme_color: string | null
  blocks: ArticleBlock[]
}

export async function saveArticle(id: string, payload: SaveArticlePayload): Promise<void> {
  const db = createAdminClient()
  const { error } = await db
    .from('xene_articles')
    .update(payload)
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/articles')
  revalidatePath(`/dashboard/articles/${id}`)
}

export async function deleteArticle(id: string): Promise<void> {
  const db = createAdminClient()
  const { error } = await db
    .from('xene_articles')
    .delete()
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/articles')
}

export async function publishArticle(id: string): Promise<void> {
  const db = createAdminClient()
  const { error } = await db
    .from('xene_articles')
    .update({ status: 'published' as ArticleStatus, published_at: new Date().toISOString() })
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/articles')
  revalidatePath(`/dashboard/articles/${id}`)
}

export async function unpublishArticle(id: string): Promise<void> {
  const db = createAdminClient()
  const { error } = await db
    .from('xene_articles')
    .update({ status: 'draft' as ArticleStatus, published_at: null })
    .eq('id', id)

  if (error) throw new Error(error.message)
  revalidatePath('/dashboard/articles')
  revalidatePath(`/dashboard/articles/${id}`)
}

export async function uploadArticleMedia(formData: FormData): Promise<string> {
  const file = formData.get('file') as File
  if (!file) throw new Error('No file provided')

  const ext = file.name.split('.').pop() ?? 'bin'
  const path = `${Date.now()}-${Math.random().toString(36).slice(2, 7)}.${ext}`

  const db = createAdminClient()
  const { error } = await db.storage
    .from('xene-media')
    .upload(path, file, { upsert: false })

  if (error) throw new Error(error.message)

  const { data } = db.storage.from('xene-media').getPublicUrl(path)
  return data.publicUrl
}
