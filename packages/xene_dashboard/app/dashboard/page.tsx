import { createAdminClient } from '@/lib/supabase/server'
import { OverviewCards } from '@/components/dashboard/overview-cards'

async function getStats() {
  const db = createAdminClient()

  const [
    { count: userCount, data: users },
    { data: activeCover },
    { count: presetCount, data: presets },
    { count: artistCount, data: artists },
    { count: articleCount, data: articles },
    { count: pubCount, data: publications },
  ] = await Promise.all([
    db
      .from('profiles')
      .select('id, email, username, role, created_at', { count: 'exact' })
      .order('created_at', { ascending: false })
      .limit(10),
    db
      .from('magazine_covers')
      .select('title')
      .eq('active', true)
      .maybeSingle(),
    db
      .from('preset_templates')
      .select('id, slug, name, enabled', { count: 'exact' })
      .eq('enabled', true)
      .limit(10),
    db
      .from('artists')
      .select('id, name, entity_type', { count: 'exact' })
      .limit(10),
    db
      .from('artist_articles')
      .select('id, artist_name, title, discovered_at', { count: 'exact' })
      .gte('discovered_at', new Date(Date.now() - 7 * 86400000).toISOString())
      .order('discovered_at', { ascending: false })
      .limit(10),
    db
      .from('press_publications')
      .select('id, name, enabled', { count: 'exact' })
      .eq('enabled', true)
      .limit(10),
  ])

  return {
    userCount: userCount ?? 0,
    users: users ?? [],
    activeCoverTitle: activeCover?.title ?? 'None',
    presetCount: presetCount ?? 0,
    presets: presets ?? [],
    artistCount: artistCount ?? 0,
    artists: artists ?? [],
    articleCount: articleCount ?? 0,
    articles: articles ?? [],
    pubCount: pubCount ?? 0,
    publications: publications ?? [],
  }
}

export default async function OverviewPage() {
  const stats = await getStats()

  return (
    <div className="p-8 space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Overview</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Live snapshot from Supabase.
        </p>
      </div>

      <OverviewCards {...stats} />
    </div>
  )
}
