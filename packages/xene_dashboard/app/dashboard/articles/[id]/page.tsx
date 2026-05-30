import { notFound } from 'next/navigation'
import { createAdminClient } from '@/lib/supabase/server'
import { ArticleEditorClient } from '@/components/articles/article-editor-client'
import type { XeneArticle } from '@/lib/types/database'

export const dynamic = 'force-dynamic'

export default async function ArticleEditorPage({
  params,
}: {
  params: { id: string }
}) {
  const db = createAdminClient()
  const { data, error } = await db
    .from('xene_articles')
    .select('*')
    .eq('id', params.id)
    .single()

  if (error || !data) notFound()

  return <ArticleEditorClient article={data as XeneArticle} />
}
