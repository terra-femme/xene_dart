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
import Link from 'next/link'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { Pencil } from 'lucide-react'

export const dynamic = 'force-dynamic'

export default async function PresetsPage() {
  const db = createAdminClient()
  const { data: presets, error } = await db
    .from('preset_templates')
    .select('id, slug, name, notch_index, theme_color, enabled, is_public, is_default, version')
    .order('notch_index', { ascending: true })

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Presets</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Preset templates that appear on the dial in the Flutter app. Edit sources via the Dart Frog backend.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: preset_templates
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, slug, name, notch_index, theme_color, enabled, is_public, is_default, version')
.order('notch_index', { ascending: true })
Total: ${presets?.length ?? 0}`}</pre>
        </div>
      </div>

      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Notch</TableHead>
              <TableHead>Slug</TableHead>
              <TableHead>Name</TableHead>
              <TableHead>Color</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>v</TableHead>
              <TableHead className="text-right">Edit</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {(presets ?? []).map((p) => (
              <TableRow key={p.id}>
                <TableCell className="text-muted-foreground">{p.notch_index}</TableCell>
                <TableCell className="font-mono text-xs">{p.slug}</TableCell>
                <TableCell>{p.name}</TableCell>
                <TableCell>
                  <div className="flex items-center gap-2">
                    <div
                      className="h-4 w-4 rounded-full border border-border"
                      style={{ backgroundColor: p.theme_color }}
                    />
                    <span className="text-xs text-muted-foreground font-mono">
                      {p.theme_color}
                    </span>
                  </div>
                </TableCell>
                <TableCell>
                  <div className="flex gap-1 flex-wrap">
                    {p.enabled ? (
                      <Badge className="bg-emerald-600/20 text-emerald-400 border-emerald-600/30 text-xs">
                        Enabled
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="text-muted-foreground text-xs">
                        Disabled
                      </Badge>
                    )}
                    {p.is_default && (
                      <Badge variant="secondary" className="text-xs">Default</Badge>
                    )}
                    {p.is_public && (
                      <Badge variant="outline" className="text-xs">Public</Badge>
                    )}
                  </div>
                </TableCell>
                <TableCell className="text-muted-foreground text-sm">{p.version}</TableCell>
                <TableCell className="text-right">
                  <Link
                    href={`/dashboard/presets/${p.slug}`}
                    className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
                  >
                    <Pencil className="h-4 w-4" />
                  </Link>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
