'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface Props {
  token: string
  backendUrl: string
}

export function MonitorClient({ token, backendUrl }: Props) {
  const [stats, setStats] = useState<Record<string, unknown> | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [lastFetch, setLastFetch] = useState<Date | null>(null)

  async function fetchStats() {
    try {
      const res = await fetch(`${backendUrl}/monitor`, {
        headers: { Authorization: `Bearer ${token}` },
      })
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`)
      const data = await res.json()
      setStats(data)
      setLastFetch(new Date())
      setError(null)
    } catch (e) {
      setError((e as Error).message)
    }
  }

  useEffect(() => {
    fetchStats()
    const interval = setInterval(fetchStats, 15000)
    return () => clearInterval(interval)
  }, [token, backendUrl])

  if (error) {
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

  if (!stats) {
    return (
      <p className="text-sm text-muted-foreground animate-pulse">
        Connecting to backend…
      </p>
    )
  }

  return (
    <div className="space-y-4">
      {lastFetch && (
        <p className="text-xs text-muted-foreground">
          Last updated: {lastFetch.toLocaleTimeString()} (auto-refreshes every 15s)
        </p>
      )}
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
  )
}
