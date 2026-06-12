import { createAdminClient } from '@/lib/supabase/server'
import { SocialAnalytics } from '@/components/social/social-analytics'
import type { SocialMetric, SocialPlatform } from '@/lib/types/database'

export const dynamic = 'force-dynamic'

export default async function SocialPage() {
  const db = createAdminClient()

  const thirtyDaysAgo = new Date(Date.now() - 30 * 86_400_000)
    .toISOString()
    .split('T')[0]

  const { data: metrics } = await db
    .from('social_metrics')
    .select('*')
    .eq('org_id', 'xene')
    .gte('metric_date', thirtyDaysAgo)
    .order('metric_date', { ascending: true })

  // Latest snapshot per platform for stat cards
  const latestByPlatform: Record<string, SocialMetric> = {}
  for (const row of (metrics ?? []) as SocialMetric[]) {
    latestByPlatform[row.platform] = row
  }

  // Determine which platforms have env vars configured (server-only check)
  const configuredPlatforms: SocialPlatform[] = []
  if (process.env.YOUTUBE_API_KEY && process.env.XENE_YOUTUBE_CHANNEL_ID)
    configuredPlatforms.push('youtube')
  if (process.env.SC_CLIENT_ID && process.env.XENE_SOUNDCLOUD_USERNAME)
    configuredPlatforms.push('soundcloud')

  return (
    <div className="p-8 space-y-8">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Social Analytics</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Xene-owned platform metrics — daily snapshots, last 30 days.
        </p>
      </div>

      <SocialAnalytics
        metrics={(metrics ?? []) as SocialMetric[]}
        latestByPlatform={latestByPlatform}
        configuredPlatforms={configuredPlatforms}
      />
    </div>
  )
}
