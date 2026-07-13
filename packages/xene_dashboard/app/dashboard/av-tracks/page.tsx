import { createAdminClient } from '@/lib/supabase/server'
import { AvTracksClient } from '@/components/av-tracks/av-tracks-client'
import type { AvTrackRow } from './actions'

export const dynamic = 'force-dynamic'

export default async function AvTracksPage() {
  const db = createAdminClient()
  const { data: tracks, error } = await db
    .from('av_tracks')
    .select('id, title, artist, position, crop_start_s, duration_s, files, settings, chart_path, created_at')
    .order('position', { ascending: true })

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">AV Tracks</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Playlist for the AV visualizer: 30s crops exported from the lab, with their reactivity settings.
          Every change here regenerates the public <span className="font-mono">playlist.json</span> the app fetches.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: av_tracks · Bucket: av-tracks
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, title, artist, position, crop_start_s, duration_s, files, settings, chart_path, created_at')
.order('position', { ascending: true })
Total: ${tracks?.length ?? 0}`}</pre>
        </div>
      </div>

      <AvTracksClient tracks={(tracks ?? []) as AvTrackRow[]} />
    </div>
  )
}
