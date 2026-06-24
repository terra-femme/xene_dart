'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Props {
  token: string
  backendUrl: string
}

interface CacheMetrics {
  connected: boolean
  uptime_seconds: number
  total_operations: number
  get_hits: number
  get_misses: number
  hit_ratio_percent: number
  set_operations: number
  delete_operations: number
  average_latency_ms: number
  total_latency_ms: number
  memory_used_bytes: number
  memory_used_mb: string
}

function ProgressBar({ value, max, label, color = 'bg-green-500' }: { value: number; max: number; label: string; color?: string }) {
  const percentage = Math.min((value / max) * 100, 100)
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-xs">
        <span className="text-muted-foreground">{label}</span>
        <span className="font-medium">{value} / {max}</span>
      </div>
      <div className="w-full bg-muted rounded-full h-2 overflow-hidden">
        <div
          className={`h-full ${color} transition-all duration-500`}
          style={{ width: `${percentage}%` }}
        />
      </div>
    </div>
  )
}

export function MonitorClient({ token, backendUrl }: Props) {
  const [stats, setStats] = useState<Record<string, unknown> | null>(null)
  const [cacheMetrics, setCacheMetrics] = useState<CacheMetrics | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [cacheError, setCacheError] = useState<string | null>(null)
  const [lastFetch, setLastFetch] = useState<Date | null>(null)

  async function fetchStats() {
    try {
      console.log('[MonitorClient] Fetching /monitor from', backendUrl)
      const res = await fetch(`${backendUrl}/monitor`, {
        headers: { Authorization: `Bearer ${token}` },
      })
      console.log('[MonitorClient] /monitor response status:', res.status)
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
      const data = await res.json()
      console.log('[MonitorClient] /monitor data:', data)
      setStats(data)
      setError(null)
    } catch (e) {
      console.error('[MonitorClient] /monitor fetch failed:', e)
      setError((e as Error).message)
    }

    try {
      console.log('[MonitorClient] Fetching /monitor/cache from', backendUrl)
      const res = await fetch(`${backendUrl}/monitor/cache`, {
        headers: { Authorization: `Bearer ${token}` },
      })
      console.log('[MonitorClient] /monitor/cache response status:', res.status)
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
      const data = (await res.json()) as CacheMetrics
      console.log('[MonitorClient] /monitor/cache data:', data)
      console.log('[MonitorClient] cache connected field:', data.connected)
      setCacheMetrics(data)
      setCacheError(null)
    } catch (e) {
      console.error('[MonitorClient] /monitor/cache fetch failed:', e)
      setCacheError((e as Error).message)
    }

    setLastFetch(new Date())
  }

  useEffect(() => {
    fetchStats()
    const interval = setInterval(fetchStats, 15000)
    return () => clearInterval(interval)
  }, [token, backendUrl])

  if (error && !stats && cacheError && !cacheMetrics) {
    return (
      <Card>
        <CardContent className="pt-6">
          <p className="text-sm text-destructive">
            Could not reach backend: {error}
          </p>
          <p className="text-xs text-muted-foreground mt-1">
            Make sure the Dart Frog backend is running at {backendUrl}
          </p>
        </CardContent>
      </Card>
    )
  }

  return (
    <div className="space-y-6">
      {lastFetch && (
        <p className="text-xs text-muted-foreground">
          Last updated: {lastFetch.toLocaleTimeString()} (auto-refreshes every 15s)
        </p>
      )}

      {/* Cache Metrics Section */}
      {cacheMetrics && (
        <div>
          <h2 className="text-lg font-semibold mb-4">Cache Performance</h2>
          <div className="grid gap-4 grid-cols-1 lg:grid-cols-2">
            {/* Hit Ratio Card */}
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Cache Hit Ratio</CardTitle>
              </CardHeader>
              <CardContent className="space-y-3">
                <div>
                  <div className="text-3xl font-bold text-green-600">
                    {cacheMetrics.hit_ratio_percent.toFixed(1)}%
                  </div>
                  <p className="text-xs text-muted-foreground mt-1">
                    {cacheMetrics.get_hits} hits / {cacheMetrics.get_hits + cacheMetrics.get_misses} total GETs
                  </p>
                </div>
                <div className="pt-2 space-y-2">
                  <ProgressBar value={cacheMetrics.get_hits} max={cacheMetrics.get_hits + cacheMetrics.get_misses} label="Hits" color="bg-green-500" />
                  <ProgressBar value={cacheMetrics.get_misses} max={cacheMetrics.get_hits + cacheMetrics.get_misses} label="Misses" color="bg-orange-500" />
                </div>
              </CardContent>
            </Card>

            {/* Latency Card */}
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Operation Latency</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-3">
                  <div>
                    <div className="text-2xl font-bold">{cacheMetrics.average_latency_ms.toFixed(2)}ms</div>
                    <p className="text-xs text-muted-foreground">average per operation</p>
                  </div>
                  <div className="pt-2 text-xs space-y-1 text-muted-foreground">
                    <div>Total: {cacheMetrics.total_latency_ms}ms</div>
                    <div>Operations: {cacheMetrics.total_operations}</div>
                  </div>
                </div>
              </CardContent>
            </Card>

            {/* Memory Card */}
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Memory Usage</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="space-y-2">
                  <div className="text-2xl font-bold">{cacheMetrics.memory_used_mb}MB</div>
                  <p className="text-xs text-muted-foreground">
                    {(cacheMetrics.memory_used_bytes / 1024).toFixed(0)} KB
                  </p>
                </div>
              </CardContent>
            </Card>

            {/* Operations Card */}
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Cache Operations</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">GET:</span>
                  <span className="font-medium">{cacheMetrics.get_hits + cacheMetrics.get_misses}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">SET:</span>
                  <span className="font-medium">{cacheMetrics.set_operations}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">DELETE:</span>
                  <span className="font-medium">{cacheMetrics.delete_operations}</span>
                </div>
                <div className="flex justify-between pt-2 border-t">
                  <span className="text-muted-foreground">Total:</span>
                  <span className="font-medium">{cacheMetrics.total_operations}</span>
                </div>
              </CardContent>
            </Card>

            {/* Status Card */}
            <Card>
              <CardHeader className="pb-3">
                <CardTitle className="text-sm font-medium">Cache Status</CardTitle>
              </CardHeader>
              <CardContent className="space-y-2">
                <div className="flex items-center gap-2">
                  <div className={`w-2 h-2 rounded-full ${cacheMetrics.connected ? 'bg-green-500' : 'bg-red-500'}`} />
                  <span className="text-sm font-medium">{cacheMetrics.connected ? 'Connected' : 'Disconnected'}</span>
                </div>
                <p className="text-xs text-muted-foreground">
                  Uptime: {Math.floor(cacheMetrics.uptime_seconds / 3600)}h {Math.floor((cacheMetrics.uptime_seconds % 3600) / 60)}m
                </p>
              </CardContent>
            </Card>
          </div>
        </div>
      )}

      {cacheError && (
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-orange-600">Cache metrics unavailable: {cacheError}</p>
          </CardContent>
        </Card>
      )}

      {/* General Stats Section */}
      {stats && (
        <div>
          <h2 className="text-lg font-semibold mb-4">Backend Statistics</h2>
          <div className="grid gap-4 grid-cols-1 lg:grid-cols-2">
            {Object.entries(stats).map(([key, value]) => (
              <Card key={key}>
                <CardHeader className="pb-2">
                  <CardTitle className="text-sm font-medium capitalize">
                    {key.replace(/([A-Z])/g, ' $1').trim()}
                  </CardTitle>
                </CardHeader>
                <CardContent>
                  <pre className="text-xs text-muted-foreground whitespace-pre-wrap overflow-auto max-h-48">
                    {JSON.stringify(value, null, 2)}
                  </pre>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      )}

      {!stats && error && (
        <Card>
          <CardContent className="pt-6">
            <p className="text-sm text-orange-600">Backend stats unavailable: {error}</p>
          </CardContent>
        </Card>
      )}

      {!stats && !error && !cacheMetrics && (
        <p className="text-sm text-muted-foreground animate-pulse">
          Connecting to backend…
        </p>
      )}
    </div>
  )
}
