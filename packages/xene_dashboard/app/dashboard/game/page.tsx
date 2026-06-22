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
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export const dynamic = 'force-dynamic'

export default async function GamePage() {
  const db = createAdminClient()

  const [{ data: parties }, { count: memberCount }, { count: trackCount }] =
    await Promise.all([
      db
        .from('game_parties')
        .select('id, name, created_by, invite_code, is_active, created_at')
        .order('created_at', { ascending: false })
        .limit(50),
      db.from('party_members').select('*', { count: 'exact', head: true }),
      db.from('party_tracks').select('*', { count: 'exact', head: true }),
    ])

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Game</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Party game stats — read-only view.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-3">
        <p className="text-xs font-semibold text-foreground">Data Sources</p>
        <div className="grid gap-3 grid-cols-3">
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Parties</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('game_parties')
.select('...')
.order('created_at', desc)
.limit(50)
Total: ${parties?.length ?? 0}`}</pre>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Members</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('party_members')
.select('*', { count: 'exact' })
Total: ${memberCount ?? 0}`}</pre>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Tracks</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('party_tracks')
.select('*', { count: 'exact' })
Total: ${trackCount ?? 0}`}</pre>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground font-medium">
              Total Parties
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">{parties?.length ?? 0}</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground font-medium">
              Party Members
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">{memberCount ?? 0}</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground font-medium">
              Tracks Submitted
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">{trackCount ?? 0}</p>
          </CardContent>
        </Card>
      </div>

      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Party Name</TableHead>
              <TableHead>Invite Code</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(parties ?? []).map((p) => (
              <TableRow key={p.id}>
                <TableCell className="font-medium">{p.name}</TableCell>
                <TableCell className="font-mono text-xs text-muted-foreground">
                  {p.invite_code}
                </TableCell>
                <TableCell>
                  {p.is_active ? (
                    <Badge className="bg-emerald-600/20 text-emerald-400 border-emerald-600/30 text-xs">
                      Active
                    </Badge>
                  ) : (
                    <Badge variant="outline" className="text-muted-foreground text-xs">
                      Inactive
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {new Date(p.created_at).toLocaleDateString()}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
