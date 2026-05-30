import { notFound } from 'next/navigation'
import { createAdminClient } from '@/lib/supabase/server'
import { CoverEditorClient } from '@/components/magazine/cover-editor-client'

export const dynamic = 'force-dynamic'

export default async function CoverEditorPage({
  params,
}: {
  params: Promise<{ id: string }>
}) {
  const db = createAdminClient()
  const { id } = await params

  const [coverResult, articlesResult] = await Promise.all([
    db.from('magazine_covers').select('*').eq('id', id).single(),
    // Graceful fallback: xene_articles table may not exist yet if migration hasn't run
    db
      .from('xene_articles')
      .select('slug, title')
      .eq('status', 'published')
      .order('title', { ascending: true })
      .then((r) => r)
      .catch(() => ({ data: [], error: null })),
  ])

  if (coverResult.error || !coverResult.data) notFound()

  const publishedArticles = (articlesResult.data ?? []) as { slug: string; title: string }[]

  return (
    <CoverEditorClient cover={coverResult.data} publishedArticles={publishedArticles} />
  )
}
