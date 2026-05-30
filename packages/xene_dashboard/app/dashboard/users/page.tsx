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
