'use client'

import { useEffect, useState } from 'react'
import type { MagazineHotspot } from '@/lib/types/database'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Button } from '@/components/ui/button'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Trash2 } from 'lucide-react'
import { Separator } from '@/components/ui/separator'

interface PublishedArticle {
  slug: string
  title: string
}

interface HotspotPanelProps {
  hotspot: MagazineHotspot | null
  onUpdate: (updated: MagazineHotspot) => void
  onDelete: (id: string) => void
  publishedArticles?: PublishedArticle[]
}

const XENE_PREFIX = 'xene://article/'

function isXeneLink(url: string | null): boolean {
  return !!url?.startsWith(XENE_PREFIX)
}

export function HotspotPanel({ hotspot, onUpdate, onDelete, publishedArticles = [] }: HotspotPanelProps) {
  const [local, setLocal] = useState<MagazineHotspot | null>(null)
  const [linkMode, setLinkMode] = useState<'external' | 'xene'>('external')

  useEffect(() => {
    setLocal(hotspot)
    setLinkMode(isXeneLink(hotspot?.article_url ?? null) ? 'xene' : 'external')
  }, [hotspot?.id])

  if (!local) {
    return (
      <div className="rounded-lg border border-dashed border-border p-6 text-center">
        <p className="text-xs text-muted-foreground">
          Select a hotspot on the preview or click the cover to add one.
        </p>
      </div>
    )
  }

  function field<K extends keyof MagazineHotspot>(key: K, value: MagazineHotspot[K]) {
    const updated = { ...local!, [key]: value }
    setLocal(updated)
    onUpdate(updated)
  }

  function handleLinkModeChange(mode: 'external' | 'xene') {
    setLinkMode(mode)
    // Clear article_url when switching modes to avoid stale values
    const updated = { ...local!, article_url: null }
    setLocal(updated)
    onUpdate(updated)
  }

  function handleArticleSelect(slug: string) {
    const url = slug ? `${XENE_PREFIX}${slug}` : null
    field('article_url', url)
  }

  const currentArticleSlug = local.article_url?.startsWith(XENE_PREFIX)
    ? local.article_url.slice(XENE_PREFIX.length)
    : ''

  return (
    <div className="rounded-lg border border-border p-4 space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium">Hotspot — {local.id}</p>
        <Button
          variant="ghost"
          size="sm"
          onClick={() => onDelete(local.id)}
          className="text-destructive hover:text-destructive"
        >
          <Trash2 className="h-4 w-4" />
        </Button>
      </div>

      <Separator />

      <div className="space-y-3">
        <div className="space-y-1">
          <Label htmlFor="hs-title">Title</Label>
          <Input
            id="hs-title"
            value={local.title}
            onChange={(e) => field('title', e.target.value)}
            placeholder="e.g. SATIATE HER FEED"
          />
        </div>

        <div className="space-y-1">
          <Label htmlFor="hs-body">Body text (optional)</Label>
          <Textarea
            id="hs-body"
            value={local.body ?? ''}
            onChange={(e) => field('body', e.target.value || null)}
            placeholder="Shown in bottom sheet"
            rows={2}
          />
        </div>

        {/* Link type toggle */}
        <div className="space-y-2">
          <Label>Link</Label>
          <div className="flex gap-1 rounded-md border border-border p-0.5 w-fit">
            <button
              type="button"
              onClick={() => handleLinkModeChange('external')}
              className={`px-3 py-1 text-xs rounded transition-colors ${
                linkMode === 'external'
                  ? 'bg-accent text-foreground'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              External URL
            </button>
            <button
              type="button"
              onClick={() => handleLinkModeChange('xene')}
              className={`px-3 py-1 text-xs rounded transition-colors ${
                linkMode === 'xene'
                  ? 'bg-accent text-foreground'
                  : 'text-muted-foreground hover:text-foreground'
              }`}
            >
              Xene Article
            </button>
          </div>

          {linkMode === 'external' ? (
            <Input
              type="url"
              value={local.article_url ?? ''}
              onChange={(e) => field('article_url', e.target.value || null)}
              placeholder="https://…"
              className="text-xs"
            />
          ) : (
            <>
              {publishedArticles.length === 0 ? (
                <p className="text-xs text-muted-foreground">
                  No published articles yet. Publish an article in Xene Articles first.
                </p>
              ) : (
                <Select
                  value={currentArticleSlug}
                  onValueChange={(v) => v && handleArticleSelect(v)}
                >
                  <SelectTrigger className="text-xs">
                    <SelectValue placeholder="Select an article…" />
                  </SelectTrigger>
                  <SelectContent>
                    {publishedArticles.map((a) => (
                      <SelectItem key={a.slug} value={a.slug} className="text-xs">
                        {a.title}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
              {local.article_url && (
                <p className="text-xs text-muted-foreground font-mono break-all">
                  {local.article_url}
                </p>
              )}
            </>
          )}
        </div>

        <div className="grid grid-cols-2 gap-2 pt-1">
          {(['x', 'y', 'width', 'height'] as const).map((k) => (
            <div key={k} className="space-y-1">
              <Label className="text-xs uppercase text-muted-foreground">{k}</Label>
              <Input
                type="number"
                step="0.01"
                min="0"
                max="1"
                value={local[k].toFixed(3)}
                onChange={(e) => field(k, parseFloat(e.target.value) || 0)}
                className="text-xs h-8"
              />
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
