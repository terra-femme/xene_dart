'use client'

import { useState, useTransition } from 'react'
import {
  addFeaturedArticle,
  deleteFeaturedArticle,
  toggleFeaturedActive,
  moveFeaturedArticle,
  updateFeaturedArticle,
  type FeaturedArticlePayload,
} from '@/app/dashboard/featured/actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Switch } from '@/components/ui/switch'
import { Textarea } from '@/components/ui/textarea'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { ChevronUp, ChevronDown, Pencil, Trash2, Plus, Import } from 'lucide-react'

interface FeaturedArticle {
  id: string
  title: string
  url: string
  snippet: string | null
  source: string | null
  image_url: string | null
  sort_order: number
  active: boolean
  published_at: string | null
}

interface PressArticle {
  title: string
  url: string
  snippet: string
  source: string
  image_url: string
  published_at: string | null
}

interface Props {
  featured: FeaturedArticle[]
  pressArticles: PressArticle[]
}

const emptyForm = (): FeaturedArticlePayload => ({
  title: '',
  url: '',
  snippet: '',
  source: '',
  image_url: '',
  published_at: null,
})

export function FeaturedManager({ featured, pressArticles }: Props) {
  const [isPending, startTransition] = useTransition()
  const [items, setItems] = useState<FeaturedArticle[]>(featured)
  const [editTarget, setEditTarget] = useState<FeaturedArticle | null>(null)
  const [showAddDialog, setShowAddDialog] = useState(false)
  const [form, setForm] = useState<FeaturedArticlePayload>(emptyForm())
  const [showImportDialog, setShowImportDialog] = useState(false)
  const [importSearch, setImportSearch] = useState('')

  const filteredPress = pressArticles.filter(
    (a) =>
      !importSearch ||
      a.title.toLowerCase().includes(importSearch.toLowerCase()) ||
      a.source.toLowerCase().includes(importSearch.toLowerCase()),
  )

  function openAdd() {
    setEditTarget(null)
    setForm(emptyForm())
    setShowAddDialog(true)
  }

  function openEdit(item: FeaturedArticle) {
    setEditTarget(item)
    setForm({
      title: item.title,
      url: item.url,
      snippet: item.snippet ?? '',
      source: item.source ?? '',
      image_url: item.image_url ?? '',
      published_at: item.published_at,
    })
    setShowAddDialog(true)
  }

  function importPress(a: PressArticle) {
    setForm({
      title: a.title,
      url: a.url,
      snippet: a.snippet,
      source: a.source,
      image_url: a.image_url,
      published_at: a.published_at,
    })
    setShowImportDialog(false)
    setEditTarget(null)
    setShowAddDialog(true)
  }

  function handleSubmit() {
    startTransition(async () => {
      if (editTarget) {
        await updateFeaturedArticle(editTarget.id, form)
        setItems((prev) =>
          prev.map((i) => (i.id === editTarget.id ? { ...i, ...form } : i)),
        )
      } else {
        await addFeaturedArticle(form)
        // Full reload to get the new id from the server
        window.location.reload()
      }
      setShowAddDialog(false)
      setForm(emptyForm())
      setEditTarget(null)
    })
  }

  function handleDelete(id: string) {
    if (!confirm('Remove this article from the Feature Strip?')) return
    startTransition(async () => {
      await deleteFeaturedArticle(id)
      setItems((prev) => prev.filter((i) => i.id !== id))
    })
  }

  function handleToggle(id: string, active: boolean) {
    startTransition(async () => {
      await toggleFeaturedActive(id, active)
      setItems((prev) => prev.map((i) => (i.id === id ? { ...i, active } : i)))
    })
  }

  function handleMove(id: string, direction: 'up' | 'down') {
    startTransition(async () => {
      await moveFeaturedArticle(id, direction)
      setItems((prev) => {
        const arr = [...prev]
        const idx = arr.findIndex((i) => i.id === id)
        const swapIdx = direction === 'up' ? idx - 1 : idx + 1
        if (swapIdx < 0 || swapIdx >= arr.length) return prev
        ;[arr[idx], arr[swapIdx]] = [arr[swapIdx], arr[idx]]
        return arr
      })
    })
  }

  return (
    <div>
      {/* Toolbar */}
      <div className="flex gap-2 mb-5">
        <Button size="sm" onClick={openAdd} disabled={isPending}>
          <Plus className="h-3.5 w-3.5 mr-1.5" />
          Add Manually
        </Button>
        <Button
          size="sm"
          variant="outline"
          onClick={() => { setImportSearch(''); setShowImportDialog(true) }}
          disabled={isPending}
        >
          <Import className="h-3.5 w-3.5 mr-1.5" />
          Import from Press ({pressArticles.length})
        </Button>
      </div>

      {/* List */}
      {items.length === 0 ? (
        <p className="text-sm text-muted-foreground py-12 text-center border border-dashed border-border rounded-md">
          No featured articles yet — add one above to populate the Feature Strip.
        </p>
      ) : (
        <div className="border border-border rounded-md overflow-hidden divide-y divide-border">
          {items.map((item, idx) => (
            <div
              key={item.id}
              className="flex items-center gap-3 px-4 py-3 bg-card hover:bg-accent/20 transition-colors"
            >
              {/* Thumbnail */}
              <div className="w-16 h-11 flex-shrink-0 rounded overflow-hidden bg-muted border border-border">
                {item.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img
                    src={item.image_url}
                    alt=""
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-[9px] text-muted-foreground font-mono tracking-wider">
                    NO IMG
                  </div>
                )}
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium truncate leading-tight">{item.title}</p>
                <p className="text-xs text-muted-foreground truncate mt-0.5">
                  {item.source && (
                    <span className="text-primary font-mono mr-2 uppercase text-[10px]">
                      {item.source}
                    </span>
                  )}
                  <span className="opacity-60">{item.url}</span>
                </p>
              </div>

              {/* Active */}
              <Switch
                checked={item.active}
                onCheckedChange={(v) => handleToggle(item.id, v)}
                disabled={isPending}
              />

              {/* Reorder */}
              <div className="flex flex-col gap-0.5 flex-shrink-0">
                <button
                  onClick={() => handleMove(item.id, 'up')}
                  disabled={idx === 0 || isPending}
                  className="p-0.5 text-muted-foreground hover:text-foreground disabled:opacity-25 transition-colors"
                >
                  <ChevronUp className="h-3.5 w-3.5" />
                </button>
                <button
                  onClick={() => handleMove(item.id, 'down')}
                  disabled={idx === items.length - 1 || isPending}
                  className="p-0.5 text-muted-foreground hover:text-foreground disabled:opacity-25 transition-colors"
                >
                  <ChevronDown className="h-3.5 w-3.5" />
                </button>
              </div>

              {/* Edit */}
              <button
                onClick={() => openEdit(item)}
                disabled={isPending}
                className="p-1.5 text-muted-foreground hover:text-foreground transition-colors flex-shrink-0"
              >
                <Pencil className="h-3.5 w-3.5" />
              </button>

              {/* Delete */}
              <button
                onClick={() => handleDelete(item.id)}
                disabled={isPending}
                className="p-1.5 text-muted-foreground hover:text-destructive transition-colors flex-shrink-0"
              >
                <Trash2 className="h-3.5 w-3.5" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Add / Edit dialog */}
      <Dialog
        open={showAddDialog}
        onOpenChange={(o) => {
          if (!o) {
            setShowAddDialog(false)
            setEditTarget(null)
          }
        }}
      >
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>{editTarget ? 'Edit Article' : 'Add Article'}</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-1">
            <div className="space-y-1.5">
              <Label>Title *</Label>
              <Input
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
                placeholder="Article headline"
              />
            </div>
            <div className="space-y-1.5">
              <Label>URL *</Label>
              <Input
                value={form.url}
                onChange={(e) => setForm({ ...form, url: e.target.value })}
                placeholder="https://..."
              />
            </div>
            <div className="space-y-1.5">
              <Label>Source</Label>
              <Input
                value={form.source ?? ''}
                onChange={(e) => setForm({ ...form, source: e.target.value })}
                placeholder="Publication or author name"
              />
            </div>
            <div className="space-y-1.5">
              <Label>Image URL</Label>
              <Input
                value={form.image_url ?? ''}
                onChange={(e) => setForm({ ...form, image_url: e.target.value })}
                placeholder="https://... (shown as card thumbnail)"
              />
              {form.image_url && (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  src={form.image_url}
                  alt="preview"
                  className="mt-1.5 h-24 w-full object-cover rounded border border-border"
                  onError={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')}
                />
              )}
            </div>
            <div className="space-y-1.5">
              <Label>Snippet <span className="text-muted-foreground">(optional)</span></Label>
              <Textarea
                value={form.snippet ?? ''}
                onChange={(e) => setForm({ ...form, snippet: e.target.value })}
                placeholder="Short description"
                rows={2}
              />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setShowAddDialog(false)}>
              Cancel
            </Button>
            <Button
              onClick={handleSubmit}
              disabled={!form.title || !form.url || isPending}
            >
              {editTarget ? 'Save changes' : 'Add to strip'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Import from press dialog */}
      <Dialog open={showImportDialog} onOpenChange={setShowImportDialog}>
        <DialogContent className="max-w-2xl flex flex-col max-h-[80vh]">
          <DialogHeader>
            <DialogTitle>Import from Press</DialogTitle>
          </DialogHeader>
          <Input
            placeholder="Search title or source..."
            value={importSearch}
            onChange={(e) => setImportSearch(e.target.value)}
            className="flex-shrink-0"
          />
          <div className="overflow-y-auto flex-1 divide-y divide-border border border-border rounded-md mt-1">
            {filteredPress.length === 0 ? (
              <p className="text-sm text-muted-foreground p-6 text-center">
                {pressArticles.length === 0
                  ? 'No press articles found — run the press scout first.'
                  : 'No results for that search.'}
              </p>
            ) : (
              filteredPress.map((a, i) => (
                <button
                  key={i}
                  onClick={() => importPress(a)}
                  className="w-full flex items-center gap-3 px-4 py-3 text-left hover:bg-accent/30 transition-colors"
                >
                  <div className="w-14 h-10 flex-shrink-0 rounded overflow-hidden bg-muted border border-border">
                    {a.image_url ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={a.image_url}
                        alt=""
                        className="w-full h-full object-cover"
                        onError={(e) => ((e.currentTarget as HTMLImageElement).style.display = 'none')}
                      />
                    ) : (
                      <div className="w-full h-full flex items-center justify-center text-[8px] text-muted-foreground font-mono">
                        NO IMG
                      </div>
                    )}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium truncate">{a.title}</p>
                    <p className="text-xs text-muted-foreground">{a.source}</p>
                  </div>
                </button>
              ))
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}
