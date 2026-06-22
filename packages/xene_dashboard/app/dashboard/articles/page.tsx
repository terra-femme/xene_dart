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
import { Plus } from 'lucide-react'

import { ArticleRowActions } from '@/components/articles/article-row-actions'

export const dynamic = 'force-dynamic'

const TEMPLATE_LABELS: Record<string, string> = {
  editorial: 'Editorial',
  interview: 'Interview',
  visual_essay: 'Visual Essay',
  audio_story: 'Audio Story',
}

export default async function ArticlesPage() {
  const db = createAdminClient()
  const { data: articles, error } = await db
    .from('xene_articles')
    .select('id, slug, title, dek, author, layout_template, status, published_at, created_at')
    .order('created_at', { ascending: false })

  if (error) {
    return <div className="p-8 text-destructive">{error.message}</div>
  }

  return (
    <div className="p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Xene Articles</h1>
          <p className="text-muted-foreground text-sm mt-1">
            Original editorial content — text, images, video, and voice notes.
          </p>
        </div>
        <Link
          href="/dashboard/articles/new"
          className={cn(buttonVariants({ variant: 'default', size: 'sm' }))}
        >
          <Plus className="h-4 w-4 mr-1" />
          New Article
        </Link>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-2">
        <p className="text-xs font-semibold text-foreground">Data Source</p>
        <div className="space-y-1">
          <div className="text-xs">
            <span className="font-mono bg-muted px-2 py-1 rounded">
              Table: xene_articles
            </span>
          </div>
          <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.select('id, slug, title, dek, author, layout_template, status, published_at, created_at')
.order('created_at', { ascending: false })
Total: ${(articles ?? []).length}`}</pre>
        </div>
      </div>

      {(articles ?? []).length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-12 text-center">
          <p className="text-sm text-muted-foreground">No articles yet.</p>
          <Link
            href="/dashboard/articles/new"
            className={cn(buttonVariants({ variant: 'outline', size: 'sm' }), 'mt-4')}
          >
            Create your first article
          </Link>
        </div>
      ) : (
        <div className="rounded-lg border border-border overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Title</TableHead>
                <TableHead>Template</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Published</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {(articles ?? []).map((a) => (
                <TableRow key={a.id}>
                  <TableCell>
                    <div>
                      <p className="font-medium">{a.title}</p>
                      <p className="text-xs text-muted-foreground font-mono">{a.slug}</p>
                    </div>
                  </TableCell>
                  <TableCell>
                    <Badge variant="outline" className="text-xs">
                      {TEMPLATE_LABELS[a.layout_template] ?? a.layout_template}
                    </Badge>
                  </TableCell>
                  <TableCell>
                    {a.status === 'published' ? (
                      <Badge className="bg-emerald-600/20 text-emerald-400 border-emerald-600/30 text-xs">
                        Published
                      </Badge>
                    ) : a.status === 'scheduled' ? (
                      <Badge className="bg-amber-600/20 text-amber-400 border-amber-600/30 text-xs">
                        Scheduled
                      </Badge>
                    ) : (
                      <Badge variant="outline" className="text-muted-foreground text-xs">
                        Draft
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground">
                    {a.published_at
                      ? new Date(a.published_at).toLocaleDateString()
                      : '—'}
                  </TableCell>
                  <TableCell className="text-right">
                    <ArticleRowActions id={a.id} title={a.title} status={a.status} />
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  )
}
