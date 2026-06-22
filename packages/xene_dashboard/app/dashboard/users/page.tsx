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
import { RoleToggle } from '@/components/users/role-toggle'

export const dynamic = 'force-dynamic'

export default async function UsersPage() {
  const db = createAdminClient()
  const { data: users, error, count } = await db
    .from('profiles')
    .select('id, email, role, username, created_at', { count: 'exact' })
    .order('created_at', { ascending: false })
    .limit(100)

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Users</h1>
        <p className="text-muted-foreground text-sm mt-1">
          {count ?? 0} registered profiles (showing last 100). Toggle admin role here.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: profiles
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, email, role, username, created_at', { count: 'exact' })
.order('created_at', { ascending: false })
.limit(100)
Total: ${count ?? 0}`}</pre>
        </div>
      </div>

      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Email</TableHead>
              <TableHead>Username</TableHead>
              <TableHead>Role</TableHead>
              <TableHead>Joined</TableHead>
              <TableHead>Toggle Admin</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(users ?? []).map((u) => (
              <TableRow key={u.id}>
                <TableCell className="font-medium text-sm">
                  {u.email ?? <span className="text-muted-foreground">—</span>}
                </TableCell>
                <TableCell className="text-muted-foreground text-sm">
                  {u.username ?? '—'}
                </TableCell>
                <TableCell>
                  {u.role === 'admin' ? (
                    <Badge className="bg-purple-600/20 text-purple-400 border-purple-600/30 text-xs">
                      admin
                    </Badge>
                  ) : (
                    <Badge variant="outline" className="text-muted-foreground text-xs">
                      user
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-xs text-muted-foreground">
                  {new Date(u.created_at).toLocaleDateString()}
                </TableCell>
                <TableCell>
                  <RoleToggle id={u.id} currentRole={u.role} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
