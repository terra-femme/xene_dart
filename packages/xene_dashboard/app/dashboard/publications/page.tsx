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
import { PublicationToggles } from '@/components/publications/publication-toggles'

export const dynamic = 'force-dynamic'

export default async function PublicationsPage() {
  const db = createAdminClient()
  const { data: pubs, error } = await db
    .from('press_publications')
    .select(
      'id, name, slug, rss_url, genres, tier, enabled, last_polled, last_status, failure_count, last_error',
    )
    .order('tier', { ascending: true })
    .order('name', { ascending: true })

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Publications</h1>
        <p className="text-muted-foreground text-sm mt-1">
          RSS feeds polled for press articles. Toggle enabled/disabled directly here.
        </p>
      </div>

      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Tier</TableHead>
              <TableHead>Genres</TableHead>
              <TableHead>Last Poll</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Failures</TableHead>
              <TableHead>Enabled</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(pubs ?? []).map((p) => (
              <TableRow key={p.id}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell className="text-muted-foreground">{p.tier}</TableCell>
                <TableCell>
                  <div className="flex gap-1 flex-wrap max-w-40">
                    {(p.genres ?? []).slice(0, 3).map((g: string) => (
                      <Badge key={g} variant="outline" className="text-xs">
                        {g}
                      </Badge>
                    ))}
                    {(p.genres ?? []).length > 3 && (
                      <span className="text-xs text-muted-foreground">
                        +{(p.genres ?? []).length - 3}
                      </span>
                    )}
                  </div>
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {p.last_polled
                    ? new Date(p.last_polled).toLocaleDateString()
                    : 'Never'}
                </TableCell>
                <TableCell>
                  {p.last_status ? (
                    <Badge
                      className={`text-xs ${
                        p.last_status < 300
                          ? 'bg-emerald-600/20 text-emerald-400 border-emerald-600/30'
                          : 'bg-red-600/20 text-red-400 border-red-600/30'
                      }`}
                    >
                      {p.last_status}
                    </Badge>
                  ) : (
                    <span className="text-xs text-muted-foreground">—</span>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground text-sm">
                  {p.failure_count > 0 ? (
                    <span className="text-red-400">{p.failure_count}</span>
                  ) : (
                    p.failure_count
                  )}
                </TableCell>
                <TableCell>
                  <PublicationToggles id={p.id} enabled={p.enabled} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
