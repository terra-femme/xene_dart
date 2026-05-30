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
import { Pencil, Plus } from 'lucide-react'
import { deleteArticle, publishArticle, unpublishArticle } from './actions'

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
                    <div className="flex items-center justify-end gap-2">
                      {a.status === 'published' ? (
                        <form
                          action={async () => {
                            'use server'
                            await unpublishArticle(a.id)
                          }}
                        >
                          <button
                            type="submit"
                            className="text-xs text-muted-foreground hover:text-foreground transition-colors"
                          >
                            Unpublish
                          </button>
                        </form>
                      ) : (
                        <form
                          action={async () => {
                            'use server'
                            await publishArticle(a.id)
                          }}
                        >
                          <button
                            type="submit"
                            className="text-xs text-emerald-400 hover:text-emerald-300 transition-colors"
                          >
                            Publish
                          </button>
                        </form>
                      )}
                      <form
                        action={async () => {
                          'use server'
                          await deleteArticle(a.id)
                        }}
                      >
                        <button
                          type="submit"
                          className="text-xs text-destructive hover:text-destructive/80 transition-colors"
                          onClick={(e) => {
                            if (!confirm(`Delete "${a.title}"?`)) e.preventDefault()
                          }}
                        >
                          Delete
                        </button>
                      </form>
                      <Link
                        href={`/dashboard/articles/${a.id}`}
                        className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
                      >
                        <Pencil className="h-4 w-4" />
                      </Link>
                    </div>
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
