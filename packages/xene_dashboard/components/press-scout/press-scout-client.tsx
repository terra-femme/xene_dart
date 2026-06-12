'use client'

import { useState, useTransition } from 'react'
import { deleteArtistArticle, updateArtistArticle } from '@/app/dashboard/press-scout/actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Play, RefreshCw, Pencil, Trash2, ExternalLink, Loader2 } from 'lucide-react'

interface Article {
  id: string
  artist_id: string
  artist_name: string | null
  title: string
  url: string
  snippet: string | null
  source: string | null
  published_at: string | null
  discovered_at: string
  preset_slug: string | null
}

interface ArtistScoutStatus {
  id: string
  name: string
  last_press_scout_at: string | null
}

interface Props {
  token: string
  backendUrl: string
  initialArticles: Article[]
  artistStatuses: ArtistScoutStatus[]
}

const emptyForm = () => ({ title: '', url: '', snippet: '', source: '' })

export function PressScoutClient({
  token,
  backendUrl,
  initialArticles,
  artistStatuses,
}: Props) {
  const [isPending, startTransition] = useTransition()
  const [articles, setArticles] = useState<Article[]>(initialArticles)
  const [scoutState, setScoutState] = useState<'idle' | 'running' | 'started' | 'error'>('idle')
  const [scoutError, setScoutError] = useState<string | null>(null)
  const [filterArtist, setFilterArtist] = useState('')
  const [editTarget, setEditTarget] = useState<Article | null>(null)
  const [editForm, setEditForm] = useState(emptyForm())

  async function runScout() {
    setScoutState('running')
    setScoutError(null)
    try {
      const res = await fetch(`${backendUrl}/press-scout/run`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
      })
      if (!res.ok) {
        const body = await res.json().catch(() => ({ error: res.statusText }))
        setScoutError((body as { error?: string }).error ?? `HTTP ${res.status}`)
        setScoutState('error')
        return
      }
      setScoutState('started')
    } catch (e) {
      setScoutError((e as Error).message)
      setScoutState('error')
    }
  }

  function openEdit(article: Article) {
    setEditTarget(article)
    setEditForm({
      title: article.title,
      url: article.url,
      snippet: article.snippet ?? '',
      source: article.source ?? '',
    })
  }

  function handleSave() {
    if (!editTarget) return
    startTransition(async () => {
      await updateArtistArticle(editTarget.id, editForm)
      setArticles((prev) =>
        prev.map((a) =>
          a.id === editTarget.id
            ? {
                ...a,
                title: editForm.title,
                url: editForm.url,
                snippet: editForm.snippet || null,
                source: editForm.source || null,
              }
            : a,
        ),
      )
      setEditTarget(null)
    })
  }

  function handleDelete(id: string) {
    if (!confirm('Delete this article from press scout results?')) return
    startTransition(async () => {
      await deleteArtistArticle(id)
      setArticles((prev) => prev.filter((a) => a.id !== id))
    })
  }

  const filtered = filterArtist.trim()
    ? articles.filter((a) =>
        a.artist_name?.toLowerCase().includes(filterArtist.toLowerCase()),
      )
    : articles

  const scoutedCount = artistStatuses.filter((a) => a.last_press_scout_at).length

  return (
    <div className="space-y-5">
      {/* Staleness note */}
      <div className="rounded-md border border-amber-600/30 bg-amber-600/10 px-4 py-3 text-xs text-amber-400 space-y-1">
        <p className="font-semibold">60-day staleness window active</p>
        <p>
          "Run Scout Now" calls <span className="font-mono">scoutArticlesForActiveArtists</span>, which
          skips any artist scouted within the last 60 days. If an artist was recently scouted they will
          be silently skipped — this is expected behaviour, not an error.
        </p>
        <p>
          To force-scout a specific preset regardless of the window, the endpoint accepts{' '}
          <span className="font-mono">?preset_id=&lt;slug&gt;</span> — not yet wired to this UI.
        </p>
      </div>

      {/* Control row */}
      <div className="flex flex-wrap items-center gap-3">
        <Button
          onClick={runScout}
          disabled={scoutState === 'running'}
          size="sm"
        >
          {scoutState === 'running' ? (
            <Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" />
          ) : (
            <Play className="h-3.5 w-3.5 mr-1.5" />
          )}
          {scoutState === 'running' ? 'Starting…' : 'Run Scout Now'}
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => window.location.reload()}
        >
          <RefreshCw className="h-3.5 w-3.5 mr-1.5" />
          Refresh
        </Button>

        {scoutState === 'started' && (
          <p className="text-sm text-emerald-400">
            Scout started — takes a few minutes. Refresh to see new articles.
          </p>
        )}
        {scoutState === 'error' && (
          <p className="text-sm text-destructive">Error: {scoutError}</p>
        )}
      </div>

      {/* Artist coverage summary */}
      <div className="flex items-center gap-4 text-xs text-muted-foreground">
        <span>
          <span className="text-foreground font-medium">{scoutedCount}</span> /{' '}
          {artistStatuses.length} artists scouted
        </span>
        <span>
          <span className="text-foreground font-medium">{articles.length}</span> total
          articles in database
        </span>
        {artistStatuses.length > 0 && (
          <details className="cursor-pointer">
            <summary className="hover:text-foreground transition-colors">
              Per-artist last scout
            </summary>
            <div className="absolute z-10 mt-1 bg-popover border border-border rounded-md p-3 space-y-1 shadow-md min-w-56">
              {artistStatuses.map((a) => (
                <div key={a.id} className="flex items-center justify-between gap-8">
                  <span className="font-medium text-foreground">{a.name}</span>
                  <span className="text-muted-foreground">
                    {a.last_press_scout_at
                      ? new Date(a.last_press_scout_at).toLocaleDateString()
                      : 'Never'}
                  </span>
                </div>
              ))}
            </div>
          </details>
        )}
      </div>

      {/* Filter */}
      <div className="flex items-center gap-3">
        <Input
          placeholder="Filter by artist name…"
          value={filterArtist}
          onChange={(e) => setFilterArtist(e.target.value)}
          className="max-w-64"
        />
        {filterArtist && (
          <span className="text-xs text-muted-foreground">
            {filtered.length} of {articles.length}
          </span>
        )}
      </div>

      {/* Table */}
      {filtered.length === 0 ? (
        <div className="rounded-lg border border-dashed border-border p-12 text-center">
          <p className="text-sm text-muted-foreground">
            {articles.length === 0
              ? 'No articles scouted yet — run the scout to populate results.'
              : 'No articles match that filter.'}
          </p>
        </div>
      ) : (
        <div className="rounded-lg border border-border overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Artist</TableHead>
                <TableHead>Title</TableHead>
                <TableHead>Source</TableHead>
                <TableHead>Published</TableHead>
                <TableHead>Discovered</TableHead>
                <TableHead className="text-right">Actions</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filtered.map((a) => (
                <TableRow key={a.id}>
                  <TableCell className="font-medium text-sm whitespace-nowrap">
                    {a.artist_name ?? '—'}
                    {a.preset_slug && (
                      <Badge
                        variant="outline"
                        className="ml-2 text-[10px] text-muted-foreground"
                      >
                        {a.preset_slug}
                      </Badge>
                    )}
                  </TableCell>
                  <TableCell className="max-w-sm">
                    <div className="flex items-start gap-1.5">
                      <a
                        href={a.url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm font-medium hover:underline underline-offset-2 line-clamp-2"
                      >
                        {a.title}
                      </a>
                      <ExternalLink className="h-3 w-3 flex-shrink-0 mt-0.5 text-muted-foreground" />
                    </div>
                    {a.snippet && (
                      <p className="text-xs text-muted-foreground mt-0.5 line-clamp-1">
                        {a.snippet}
                      </p>
                    )}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground whitespace-nowrap">
                    {a.source ?? '—'}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground whitespace-nowrap">
                    {a.published_at
                      ? new Date(a.published_at).toLocaleDateString()
                      : '—'}
                  </TableCell>
                  <TableCell className="text-xs text-muted-foreground whitespace-nowrap">
                    {new Date(a.discovered_at).toLocaleDateString()}
                  </TableCell>
                  <TableCell className="text-right">
                    <div className="flex items-center justify-end gap-1">
                      <button
                        onClick={() => openEdit(a)}
                        disabled={isPending}
                        className="p-1.5 text-muted-foreground hover:text-foreground transition-colors disabled:opacity-40"
                        title="Edit"
                      >
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={() => handleDelete(a.id)}
                        disabled={isPending}
                        className="p-1.5 text-muted-foreground hover:text-destructive transition-colors disabled:opacity-40"
                        title="Delete"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}

      {/* Edit dialog */}
      <Dialog
        open={!!editTarget}
        onOpenChange={(o) => {
          if (!o) setEditTarget(null)
        }}
      >
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Edit Article</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-1">
            <div className="space-y-1.5">
              <Label>Title *</Label>
              <Input
                value={editForm.title}
                onChange={(e) => setEditForm({ ...editForm, title: e.target.value })}
                placeholder="Article headline"
              />
            </div>
            <div className="space-y-1.5">
              <Label>URL *</Label>
              <Input
                value={editForm.url}
                onChange={(e) => setEditForm({ ...editForm, url: e.target.value })}
                placeholder="https://…"
              />
            </div>
            <div className="space-y-1.5">
              <Label>Source</Label>
              <Input
                value={editForm.source}
                onChange={(e) => setEditForm({ ...editForm, source: e.target.value })}
                placeholder="Publication name"
              />
            </div>
            <div className="space-y-1.5">
              <Label>
                Snippet{' '}
                <span className="text-muted-foreground">(optional)</span>
              </Label>
              <Textarea
                value={editForm.snippet}
                onChange={(e) => setEditForm({ ...editForm, snippet: e.target.value })}
                placeholder="Short description or excerpt"
                rows={3}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditTarget(null)}>
              Cancel
            </Button>
            <Button
              onClick={handleSave}
              disabled={!editForm.title || !editForm.url || isPending}
            >
              {isPending ? (
                <Loader2 className="h-3.5 w-3.5 mr-1.5 animate-spin" />
              ) : null}
              Save changes
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}
