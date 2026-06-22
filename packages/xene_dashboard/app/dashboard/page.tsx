import { createAdminClient } from '@/lib/supabase/server'
import { DetailedStatCard } from '@/components/shared/stat-card-detailed'
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

      <div className="grid gap-4 grid-cols-2 lg:grid-cols-3">
        <DetailedStatCard
          title="Total Users"
          value={stats.userCount}
          Icon={Users}
          description="Registered profiles"
          table="profiles"
          query=".select('id, email, username, role, created_at').order('created_at', desc).limit(10)"
          filters={{ count: stats.userCount }}
          detailsContent={
            <div className="space-y-4">
              <div className="text-sm text-muted-foreground">Latest 10 users:</div>
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {stats.users.map((u: any) => (
                  <div key={u.id} className="border border-border rounded p-2 text-xs space-y-1">
                    <div><span className="font-semibold">{u.email}</span> {u.role === 'admin' && <span className="text-purple-400">(admin)</span>}</div>
                    <div className="text-muted-foreground">{u.username || '—'}</div>
                    <div className="text-muted-foreground">{new Date(u.created_at).toLocaleString()}</div>
                  </div>
                ))}
              </div>
            </div>
          }
        />
        <DetailedStatCard
          title="Active Cover"
          value={stats.activeCoverTitle}
          Icon={BookImage}
          description="Current magazine issue"
          table="magazine_covers"
          filters={{ active: true }}
          detailsContent={
            <div className="text-sm text-muted-foreground">
              {stats.activeCoverTitle === 'None' ? 'No active cover' : `Active: ${stats.activeCoverTitle}`}
            </div>
          }
        />
        <DetailedStatCard
          title="Active Presets"
          value={stats.presetCount}
          Icon={SlidersHorizontal}
          description="Enabled preset templates"
          table="preset_templates"
          query=".select('id, slug, name, enabled').eq('enabled', true).limit(10)"
          filters={{ enabled: true }}
          detailsContent={
            <div className="space-y-4">
              <div className="text-sm text-muted-foreground">Active presets (showing 10):</div>
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {stats.presets.map((p: any) => (
                  <div key={p.id} className="border border-border rounded p-2 text-xs space-y-1">
                    <div><span className="font-semibold">{p.name}</span></div>
                    <div className="text-muted-foreground font-mono">{p.slug}</div>
                  </div>
                ))}
              </div>
            </div>
          }
        />
        <DetailedStatCard
          title="Total Artists"
          value={stats.artistCount}
          Icon={Mic2}
          description="In global artist database"
          table="artists"
          query=".select('id, name, entity_type').limit(10)"
          filters={{ total_count: stats.artistCount }}
          detailsContent={
            <div className="space-y-4">
              <div className="text-sm text-muted-foreground">Sample artists (showing 10):</div>
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {stats.artists.map((a: any) => (
                  <div key={a.id} className="border border-border rounded p-2 text-xs space-y-1">
                    <div><span className="font-semibold">{a.name}</span></div>
                    <div className="text-muted-foreground">{a.entity_type || 'artist'}</div>
                  </div>
                ))}
              </div>
            </div>
          }
        />
        <DetailedStatCard
          title="Articles (7d)"
          value={stats.articleCount}
          Icon={FileText}
          description="Discovered in last 7 days"
          table="artist_articles"
          query=".select('id, artist_name, title, discovered_at').gte('discovered_at', 7d-ago).order('discovered_at', desc).limit(10)"
          filters={{ discovered_last_7_days: true }}
          detailsContent={
            <div className="space-y-4">
              <div className="text-sm text-muted-foreground">Recent articles (showing 10):</div>
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {stats.articles.map((a: any) => (
                  <div key={a.id} className="border border-border rounded p-2 text-xs space-y-1">
                    <div><span className="font-semibold">{a.title}</span></div>
                    <div className="text-muted-foreground">{a.artist_name} • {new Date(a.discovered_at).toLocaleDateString()}</div>
                  </div>
                ))}
              </div>
            </div>
          }
        />
        <DetailedStatCard
          title="Active Publications"
          value={stats.pubCount}
          Icon={Newspaper}
          description="RSS feeds being polled"
          table="press_publications"
          query=".select('id, name, enabled').eq('enabled', true).limit(10)"
          filters={{ enabled: true }}
          detailsContent={
            <div className="space-y-4">
              <div className="text-sm text-muted-foreground">Active publications (showing 10):</div>
              <div className="space-y-2 max-h-96 overflow-y-auto">
                {stats.publications.map((p: any) => (
                  <div key={p.id} className="border border-border rounded p-2 text-xs">
                    <span className="font-semibold">{p.name}</span>
                  </div>
                ))}
              </div>
            </div>
          }
        />
      </div>
    </div>
  )
}
