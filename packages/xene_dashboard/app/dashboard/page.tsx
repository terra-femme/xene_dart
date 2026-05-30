import { createAdminClient } from '@/lib/supabase/server'
import { StatCard } from '@/components/shared/stat-card'
import {
  Users,
  BookImage,
  SlidersHorizontal,
  Mic2,
  Newspaper,
  FileText,
} from 'lucide-react'

async function getStats() {
  const db = createAdminClient()

  const [
    { count: userCount },
    { data: activeCover },
    { count: presetCount },
    { count: artistCount },
    { count: articleCount },
    { count: pubCount },
  ] = await Promise.all([
    db.from('profiles').select('*', { count: 'exact', head: true }),
    db
      .from('magazine_covers')
      .select('title')
      .eq('active', true)
      .maybeSingle(),
    db
      .from('preset_templates')
      .select('*', { count: 'exact', head: true })
      .eq('enabled', true),
    db.from('artists').select('*', { count: 'exact', head: true }),
    db
      .from('artist_articles')
      .select('*', { count: 'exact', head: true })
      .gte('discovered_at', new Date(Date.now() - 7 * 86400000).toISOString()),
    db
      .from('press_publications')
      .select('*', { count: 'exact', head: true })
      .eq('enabled', true),
  ])

  return {
    userCount: userCount ?? 0,
    activeCoverTitle: activeCover?.title ?? 'None',
    presetCount: presetCount ?? 0,
    artistCount: artistCount ?? 0,
    articleCount: articleCount ?? 0,
    pubCount: pubCount ?? 0,
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

      <div className="grid gap-4 grid-cols-2 lg:grid-cols-3">
        <StatCard
          title="Total Users"
          value={stats.userCount}
          Icon={Users}
          description="Registered profiles"
        />
        <StatCard
          title="Active Cover"
          value={stats.activeCoverTitle}
          Icon={BookImage}
          description="Current magazine issue"
        />
        <StatCard
          title="Active Presets"
          value={stats.presetCount}
          Icon={SlidersHorizontal}
          description="Enabled preset templates"
        />
        <StatCard
          title="Total Artists"
          value={stats.artistCount}
          Icon={Mic2}
          description="In global artist database"
        />
        <StatCard
          title="Articles (7d)"
          value={stats.articleCount}
          Icon={FileText}
          description="Discovered in last 7 days"
        />
        <StatCard
          title="Active Publications"
          value={stats.pubCount}
          Icon={Newspaper}
          description="RSS feeds being polled"
        />
      </div>
    </div>
  )
}
