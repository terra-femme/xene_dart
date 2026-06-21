import { createAdminClient } from '@/lib/supabase/server'
import { FeaturedManager } from '@/components/featured/featured-manager'

export const dynamic = 'force-dynamic'

export default async function FeaturedPage() {
  const db = createAdminClient()

  const [featuredResult, artistResult, pubResult] = await Promise.all([
    db
      .from('featured_articles')
      .select('*')
      .order('sort_order', { ascending: true }),
    Promise.resolve(
      db
        .from('artist_articles')
        .select('title, url, snippet, image_url, published_at, artists(name)')
        .order('published_at', { ascending: false })
        .limit(60)
    ).catch(() => ({ data: [], error: null })),
    Promise.resolve(
      db
        .from('publication_articles')
        .select('title, url, snippet, image_url, published_at, press_publications(name)')
        .order('published_at', { ascending: false })
        .limit(60)
    ).catch(() => ({ data: [], error: null })),
  ])

  const featured = featuredResult.data ?? []

  const pressArticles = [
    ...(artistResult.data ?? []).map((a: any) => ({
      title: (a.title as string) ?? '',
      url: (a.url as string) ?? '',
      snippet: (a.snippet as string) ?? '',
      source: (a.artists as any)?.name ?? '',
      image_url: (a.image_url as string) ?? '',
      published_at: (a.published_at as string) ?? null,
    })),
    ...(pubResult.data ?? []).map((a: any) => ({
      title: (a.title as string) ?? '',
      url: (a.url as string) ?? '',
      snippet: (a.snippet as string) ?? '',
      source: (a.press_publications as any)?.name ?? '',
      image_url: (a.image_url as string) ?? '',
      published_at: (a.published_at as string) ?? null,
    })),
  ].filter((a) => a.title && a.url)

  return (
    <div className="p-6 max-w-4xl">
      <div className="mb-6">
        <h1 className="text-xl font-semibold tracking-tight">Feature Strip</h1>
        <p className="text-sm text-muted-foreground mt-1">
          Controls the horizontal article cards on the app's Feature tab. Add manually or import from press. Set an image URL to show a thumbnail on each card.
        </p>
      </div>
      <FeaturedManager featured={featured} pressArticles={pressArticles} />
    </div>
  )
}
