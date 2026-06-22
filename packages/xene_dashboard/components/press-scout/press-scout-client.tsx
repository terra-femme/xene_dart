'use client'

import { useState, useTransition } from 'react'
import { deleteArtistArticle, updateArtistArticle, triggerPublicationPolling } from '@/app/dashboard/press-scout/actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
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
import { Play, RefreshCw, Pencil, Trash2, ExternalLink, Loader2, Zap } from 'lucide-react'

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

interface Preset {
  id: string
  slug: string
  name: string
}

interface Props {
  token: string
  backendUrl: string
  initialArticles: Article[]
  artistStatuses: ArtistScoutStatus[]
  presets?: Preset[]
}

const emptyForm = () => ({ title: '', url: '', snippet: '', source: '' })

export function PressScoutClient({
  token,
  backendUrl,
  initialArticles,
  artistStatuses,
  presets = [],
}: Props) {
  const [isPending, startTransition] = useTransition()
  const [articles, setArticles] = useState<Article[]>(initialArticles)
  const [scoutState, setScoutState] = useState<'idle' | 'running' | 'started' | 'error'>('idle')
  const [scoutError, setScoutError] = useState<string | null>(null)
  const [pollState, setPollState] = useState<'idle' | 'running' | 'started' | 'error'>('idle')
  const [pollError, setPollError] = useState<string | null>(null)
  const [selectedPreset, setSelectedPreset] = useState<string>('')
  const [filterArtist, setFilterArtist] = useState('')
  const [editTarget, setEditTarget] = useState<Article | null>(null)
  const [editForm, setEditForm] = useState(emptyForm())

  async function runScout() {
    setScoutState('running')
    setScoutError(null)
    try {
      const url = new URL(`${backendUrl}/press-scout/run`)
      if (selectedPreset) {
        url.searchParams.set('preset_id', selectedPreset)
      }
      const res = await fetch(url.toString(), {
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

  async function runPoll() {
    setPollState('running')
    setPollError(null)
    try {
      await triggerPublicationPolling(token, backendUrl, selectedPreset || undefined)
      setPollState('started')
    } catch (e) {
      setPollError((e as Error).message)
      setPollState('error')
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
      {/* Scout & Poll for Preset */}
      {presets.length > 0 && (
        <div className="rounded-lg border border-blue-600/30 bg-blue-600/10 px-4 py-4 space-y-3">
          <div>
            <h3 className="font-semibold text-blue-400 text-sm mb-2">Scout & Poll for Preset (HITL)</h3>
            <p className="text-xs text-blue-300/80 mb-3">
              Manually trigger press scout (LLM-based) and publication poller (RSS-based) for a preset.
              Review and approve/reject articles before they stay in the database.
            </p>
          </div>

          <div className="flex flex-wrap items-end gap-3">
            <div className="flex-1 min-w-48">
              <Label className="text-xs mb-1.5 block">Select Preset</Label>
              <Select value={selectedPreset} onValueChange={setSelectedPreset}>
                <SelectTrigger className="h-9 text-sm">
                  <SelectValue placeholder="Choose a preset…" />
                </SelectTrigger>
                <SelectContent>
                  {presets.map((p) => (
                    <SelectItem key={p.id} value={p.slug}>
                      {p.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <Button
              onClick={runScout}
              disabled={!selectedPreset || scoutState === 'running' || pollState === 'running'}
              size="sm"
              className="gap-2"
            >
              {scoutState === 'running' ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Play className="h-3.5 w-3.5" />
              )}
              {scoutState === 'running' ? 'Scouting…' : 'Scout'}
            </Button>

            <Button
              onClick={runPoll}
              disabled={pollState === 'running' || scoutState === 'running'}
              size="sm"
              variant="outline"
              className="gap-2"
            >
              {pollState === 'running' ? (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              ) : (
                <Zap className="h-3.5 w-3.5" />
              )}
              {pollState === 'running' ? 'Polling…' : 'Poll'}
            </Button>

            <Button
              variant="outline"
              size="sm"
              onClick={() => window.location.reload()}
            >
              <RefreshCw className="h-3.5 w-3.5" />
            </Button>
          </div>

          {scoutState === 'started' && (
            <p className="text-xs text-emerald-400">
              Press scout started — takes a few minutes. Refresh to see new articles.
            </p>
          )}
          {scoutState === 'error' && (
            <p className="text-xs text-destructive">Scout error: {scoutError}</p>
          )}
          {pollState === 'started' && (
            <p className="text-xs text-emerald-400">
              Publication poll started — takes a few minutes. Refresh to see new articles.
            </p>
          )}
          {pollState === 'error' && (
            <p className="text-xs text-destructive">Poll error: {pollError}</p>
          )}
        </div>
      )}

      {/* Staleness note */}
      <div className="rounded-md border border-amber-600/30 bg-amber-600/10 px-4 py-3 text-xs text-amber-400 space-y-1">
        <p className="font-semibold">60-day staleness window active</p>
        <p>
          "Run Scout Now" respects the 60-day staleness window — any artist scouted within the last 60 days
          will be silently skipped. When you use the "Scout & Poll for Preset" section above, it bypasses
          this window and scouts all artists in the preset immediately.
        </p>
        <p>
          Scout results appear below. Review articles before they stay in the database — delete ones that
          are hallucinated or irrelevant.
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
