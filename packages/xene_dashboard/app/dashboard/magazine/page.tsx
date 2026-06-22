import Link from 'next/link'
import { createAdminClient } from '@/lib/supabase/server'
import { CoverListTable } from '@/components/magazine/cover-list-table'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { Plus } from 'lucide-react'

export const dynamic = 'force-dynamic'

export default async function MagazinePage() {
  const db = createAdminClient()
  const { data: covers, error } = await db
    .from('magazine_covers')
    .select('id, title, aspect_ratio, active, published_at, background_image_url')
    .order('published_at', { ascending: false })

  if (error) {
    return (
      <div className="p-8 text-destructive">
        Failed to load covers: {error.message}
      </div>
    )
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Magazine Covers</h1>
          <p className="text-muted-foreground text-sm mt-1">
            One cover can be active at a time. The Flutter app renders whatever
            is active.
          </p>
        </div>
        <Link href="/dashboard/magazine/new" className={cn(buttonVariants())}>
          <Plus className="h-4 w-4 mr-2" />
          New Cover
        </Link>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: magazine_covers
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, title, aspect_ratio, active, published_at, background_image_url')
.order('published_at', { ascending: false })
Total: ${covers?.length ?? 0}`}</pre>
        </div>
      </div>

      <CoverListTable covers={covers ?? []} />
    </div>
  )
}
