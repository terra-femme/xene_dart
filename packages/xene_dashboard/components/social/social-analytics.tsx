'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { refreshMetrics } from '@/app/dashboard/social/actions'
import type { SocialMetric, SocialPlatform } from '@/lib/types/database'

const PLATFORM_META: Record<
  SocialPlatform,
  { label: string; color: string; available: boolean }
> = {
  youtube:    { label: 'YouTube',    color: '#FF0000', available: true },
  soundcloud: { label: 'SoundCloud', color: '#FF5500', available: true },
  twitch:     { label: 'Twitch',     color: '#9146FF', available: false },
  instagram:  { label: 'Instagram',  color: '#E1306C', available: false },
  tiktok:     { label: 'TikTok',     color: '#69C9D0', available: false },
}

const ALL_PLATFORMS = Object.keys(PLATFORM_META) as SocialPlatform[]

function fmt(n: number | null | undefined): string {
  if (n == null) return '—'
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`
  if (n >= 1_000) return `${(n / 1_000).toFixed(1)}K`
  return n.toString()
}

interface Props {
  metrics: SocialMetric[]
  latestByPlatform: Record<string, SocialMetric>
  configuredPlatforms: SocialPlatform[]
}

export function SocialAnalytics({ metrics, latestByPlatform, configuredPlatforms }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [statusMsg, setStatusMsg] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)

  function handleRefresh() {
    setStatusMsg(null)
    startTransition(async () => {
      const result = await refreshMetrics()
      setIsError(!result.ok)
      setStatusMsg(result.message)
      if (result.ok) router.refresh()
    })
  }

  // Build per-date rows for charts: { date, youtube_followers, soundcloud_followers, ... }
  const dateMap: Record<string, Record<string, number | null>> = {}
  for (const row of metrics) {
    if (!dateMap[row.metric_date]) dateMap[row.metric_date] = {}
    dateMap[row.metric_date][`${row.platform}_followers`] = row.followers
    dateMap[row.metric_date][`${row.platform}_views`] = row.total_views
  }
  const chartData = Object.entries(dateMap)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([date, vals]) => ({ date, ...vals }))

  const activePlatforms = ALL_PLATFORMS.filter((p) => latestByPlatform[p])

  return (
    <div className="space-y-6">
      {/* Platform status cards */}
      <div className="grid grid-cols-5 gap-3">
        {ALL_PLATFORMS.map((platform) => {
          const meta = PLATFORM_META[platform]
          const latest = latestByPlatform[platform]
          const isConfigured = configuredPlatforms.includes(platform)
          const hasData = !!latest

          return (
            <Card key={platform} className={!meta.available ? 'opacity-50' : undefined}>
              <CardContent className="pt-4 pb-3 px-4">
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-semibold" style={{ color: meta.color }}>
                    {meta.label}
                  </span>
                  {meta.available ? (
                    <span
                      className={`text-[10px] font-medium px-1.5 py-0.5 rounded-full ring-1 ring-inset ${
                        hasData
                          ? 'bg-green-500/15 text-green-600 ring-green-500/20'
                          : isConfigured
                          ? 'bg-yellow-500/15 text-yellow-600 ring-yellow-500/20'
                          : 'bg-zinc-500/15 text-zinc-500 ring-zinc-500/20'
                      }`}
                    >
                      {hasData ? 'live' : isConfigured ? 'no data' : 'unconfigured'}
                    </span>
                  ) : (
                    <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-zinc-500/15 text-zinc-500 ring-1 ring-inset ring-zinc-500/20">
                      soon
                    </span>
                  )}
                </div>

                {hasData ? (
                  <div className="space-y-1">
                    <div>
                      <p className="text-[10px] text-muted-foreground">Followers</p>
                      <p className="text-lg font-bold leading-tight">{fmt(latest.followers)}</p>
                    </div>
                    <div className="flex gap-3">
                      <div>
                        <p className="text-[10px] text-muted-foreground">Views / Plays</p>
                        <p className="text-sm font-semibold">{fmt(latest.total_views)}</p>
                      </div>
                      <div>
                        <p className="text-[10px] text-muted-foreground">Posts</p>
                        <p className="text-sm font-semibold">{fmt(latest.posts_count)}</p>
                      </div>
                    </div>
                    <p className="text-[10px] text-muted-foreground pt-0.5">
                      {latest.metric_date}
                    </p>
                  </div>
                ) : (
                  <p className="text-xs text-muted-foreground mt-1">
                    {meta.available
                      ? isConfigured
                        ? 'Click Refresh to pull first snapshot.'
                        : 'Set env vars to connect.'
                      : 'OAuth integration coming soon.'}
                  </p>
                )}
              </CardContent>
            </Card>
          )
        })}
      </div>

      {/* Refresh control */}
      <div className="flex items-center gap-4">
        <button
          onClick={handleRefresh}
          disabled={isPending}
          className="px-4 py-1.5 text-sm font-medium rounded-md bg-primary text-primary-foreground hover:bg-primary/90 disabled:opacity-50 transition-colors"
        >
          {isPending ? 'Refreshing…' : 'Refresh Metrics'}
        </button>
        {statusMsg && (
          <p className={`text-xs ${isError ? 'text-red-500' : 'text-green-600'}`}>
            {statusMsg}
          </p>
        )}
      </div>

      {/* Charts — only render when there's data */}
      {chartData.length === 0 ? (
        <Card>
          <CardContent className="py-16 flex flex-col items-center justify-center gap-2">
            <p className="text-sm font-medium">No snapshots yet</p>
            <p className="text-xs text-muted-foreground">
              Add env vars for at least one platform then click Refresh Metrics.
            </p>
          </CardContent>
        </Card>
      ) : (
        <div className="space-y-6">
          {/* Followers / Subscribers over time */}
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-medium">Followers / Subscribers (30d)</CardTitle>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={220}>
                <LineChart data={chartData}>
                  <XAxis
                    dataKey="date"
                    tick={{ fontSize: 10, fill: '#888' }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis
                    tick={{ fontSize: 10, fill: '#888' }}
                    axisLine={false}
                    tickLine={false}
                    width={40}
                    tickFormatter={(v) => fmt(v)}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1a1a1a',
                      border: '1px solid #333',
                      borderRadius: 6,
                      fontSize: 11,
                    }}
                    formatter={((value: number | undefined, name: string) => [
                      value !== undefined ? fmt(value) : '',
                      name.replace('_followers', ''),
                    ]) as any}
                  />
                  <Legend
                    wrapperStyle={{ fontSize: 11 }}
                    formatter={(value) => value.replace('_followers', '')}
                  />
                  {activePlatforms.map((p) => (
                    <Line
                      key={p}
                      type="monotone"
                      dataKey={`${p}_followers`}
                      stroke={PLATFORM_META[p].color}
                      strokeWidth={2}
                      dot={false}
                      connectNulls
                    />
                  ))}
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>

          {/* Views / Plays over time */}
          <Card>
            <CardHeader>
              <CardTitle className="text-sm font-medium">Views / Plays (30d)</CardTitle>
            </CardHeader>
            <CardContent>
              <ResponsiveContainer width="100%" height={220}>
                <LineChart data={chartData}>
                  <XAxis
                    dataKey="date"
                    tick={{ fontSize: 10, fill: '#888' }}
                    axisLine={false}
                    tickLine={false}
                  />
                  <YAxis
                    tick={{ fontSize: 10, fill: '#888' }}
                    axisLine={false}
                    tickLine={false}
                    width={40}
                    tickFormatter={(v) => fmt(v)}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: '#1a1a1a',
                      border: '1px solid #333',
                      borderRadius: 6,
                      fontSize: 11,
                    }}
                    formatter={((value: number | undefined, name: string) => [
                      value !== undefined ? fmt(value) : '',
                      name.replace('_views', ''),
                    ]) as any}
                  />
                  <Legend
                    wrapperStyle={{ fontSize: 11 }}
                    formatter={(value) => value.replace('_views', '')}
                  />
                  {activePlatforms.map((p) => (
                    <Line
                      key={p}
                      type="monotone"
                      dataKey={`${p}_views`}
                      stroke={PLATFORM_META[p].color}
                      strokeWidth={2}
                      dot={false}
                      connectNulls
                    />
                  ))}
                </LineChart>
              </ResponsiveContainer>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  )
}
