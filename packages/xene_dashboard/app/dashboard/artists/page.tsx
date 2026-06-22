import { createAdminClient } from '@/lib/supabase/server'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

export const dynamic = 'force-dynamic'

const CONFIDENCE_COLORS: Record<string, string> = {
  HIGH: 'bg-emerald-600/20 text-emerald-400 border-emerald-600/30',
  MEDIUM: 'bg-yellow-600/20 text-yellow-400 border-yellow-600/30',
  LOW: 'bg-red-600/20 text-red-400 border-red-600/30',
  UNVERIFIED: 'bg-zinc-600/20 text-zinc-400 border-zinc-600/30',
}

export default async function ArtistsPage() {
  const db = createAdminClient()
  const { data: artists, error, count } = await db
    .from('artists')
    .select(
      'id, name, entity_type, soundcloud_username, genre_tags, identity_confidence, manually_verified, last_press_scout_at',
      { count: 'exact' },
    )
    .order('name', { ascending: true })
    .limit(100)

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Artists</h1>
        <p className="text-muted-foreground text-sm mt-1">
          {count ?? 0} artists in global identity database (showing first 100).
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: artists
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, name, entity_type, soundcloud_username, genre_tags, identity_confidence, manually_verified, last_press_scout_at', { count: 'exact' })
.order('name', { ascending: true })
.limit(100)
Total: ${count ?? 0}`}</pre>
        </div>
      </div>

      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>SoundCloud</TableHead>
              <TableHead>Type</TableHead>
              <TableHead>Genres</TableHead>
              <TableHead>Confidence</TableHead>
              <TableHead>Verified</TableHead>
              <TableHead>Last Scout</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(artists ?? []).map((a) => (
              <TableRow key={a.id}>
                <TableCell className="font-medium">{a.name}</TableCell>
                <TableCell className="text-muted-foreground text-xs font-mono">
                  {a.soundcloud_username ?? '—'}
                </TableCell>
                <TableCell className="text-muted-foreground text-xs">
                  {a.entity_type}
                </TableCell>
                <TableCell>
                  <div className="flex gap-1 flex-wrap max-w-40">
                    {(a.genre_tags ?? []).slice(0, 3).map((g: string) => (
                      <Badge key={g} variant="outline" className="text-xs">
                        {g}
                      </Badge>
                    ))}
                    {(a.genre_tags ?? []).length > 3 && (
                      <span className="text-xs text-muted-foreground">
                        +{(a.genre_tags ?? []).length - 3}
                      </span>
                    )}
                  </div>
                </TableCell>
                <TableCell>
                  {a.identity_confidence ? (
                    <Badge
                      className={`text-xs ${CONFIDENCE_COLORS[a.identity_confidence] ?? ''}`}
                    >
                      {a.identity_confidence}
                    </Badge>
                  ) : (
                    <span className="text-muted-foreground text-xs">—</span>
                  )}
                </TableCell>
                <TableCell>
                  {a.manually_verified ? (
                    <span className="text-xs text-emerald-400">✓</span>
                  ) : (
                    <span className="text-xs text-muted-foreground">—</span>
                  )}
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {a.last_press_scout_at
                    ? new Date(a.last_press_scout_at).toLocaleDateString()
                    : 'Never'}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
