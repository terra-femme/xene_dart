import { createAdminClient } from '@/lib/supabase/server'
import { AnalyticsCharts } from '@/components/analytics/analytics-charts'

export const dynamic = 'force-dynamic'

export default async function AnalyticsPage() {
  const db = createAdminClient()

  // Top 10 artists by play count
  const { data: topArtists } = await db
    .from('listening_history')
    .select('artist_name')
    .not('artist_name', 'is', null)
    .gte('played_at', new Date(Date.now() - 30 * 86400000).toISOString())

  // Feed items by platform
  const { data: feedItems } = await db
    .from('feed_items')
    .select('platform')
    .gte('published_at', new Date(Date.now() - 30 * 86400000).toISOString())

  // Daily play counts (last 14 days)
  const { data: recentPlays } = await db
    .from('listening_history')
    .select('played_at')
    .gte('played_at', new Date(Date.now() - 14 * 86400000).toISOString())
    .order('played_at', { ascending: true })

  // Aggregate top artists
  const artistCounts: Record<string, number> = {}
  for (const row of topArtists ?? []) {
    const name = row.artist_name ?? 'Unknown'
    artistCounts[name] = (artistCounts[name] ?? 0) + 1
  }
  const topArtistData = Object.entries(artistCounts)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 10)
    .map(([name, count]) => ({ name, count }))

  // Aggregate platform counts
  const platformCounts: Record<string, number> = {}
  for (const row of feedItems ?? []) {
    const p = row.platform ?? 'unknown'
    platformCounts[p] = (platformCounts[p] ?? 0) + 1
  }
  const platformData = Object.entries(platformCounts).map(([name, count]) => ({
    name,
    count,
  }))

  // Aggregate plays per day
  const dayCounts: Record<string, number> = {}
  for (const row of recentPlays ?? []) {
    const day = new Date(row.played_at).toLocaleDateString('en-US', {
      month: 'short',
      day: 'numeric',
    })
    dayCounts[day] = (dayCounts[day] ?? 0) + 1
  }
  const playsPerDay = Object.entries(dayCounts).map(([date, plays]) => ({
    date,
    plays,
  }))

  return (
    <div className="p-8 space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Analytics</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Built from existing Supabase tables — last 30 days.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-3">
        <p className="text-xs font-semibold text-foreground">Data Sources (Last 30 Days)</p>
        <div className="grid gap-3 grid-cols-3">
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Top Artists</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('listening_history')
.select('artist_name')
.not('artist_name', 'is', null)
.gte('played_at', 30d-ago)
Total: ${topArtists?.length ?? 0} plays`}</pre>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">By Platform</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('feed_items')
.select('platform')
.gte('published_at', 30d-ago)
Total: ${feedItems?.length ?? 0} items`}</pre>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Plays Per Day</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('listening_history')
.select('played_at')
.gte('played_at', 14d-ago)
.order('played_at', asc)
Total: ${recentPlays?.length ?? 0} plays`}</pre>
          </div>
        </div>
      </div>

      <AnalyticsCharts
        topArtists={topArtistData}
        platformData={platformData}
        playsPerDay={playsPerDay}
      />
    </div>
  )
}
