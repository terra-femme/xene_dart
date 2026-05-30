'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import type { MagazineCover, MagazineHotspot, MagazineMotionLayer } from '@/lib/types/database'
import { saveCover, uploadCoverImage } from '@/app/dashboard/magazine/actions'
import { HotspotEditor } from './hotspot-editor'
import { HotspotPanel } from './hotspot-panel'
import { MotionLayerTable } from './motion-layer-table'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Button, buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { ArrowLeft, Save, Upload } from 'lucide-react'
import Link from 'next/link'

interface PublishedArticle {
  slug: string
  title: string
}

interface Props {
  cover: MagazineCover
  publishedArticles?: PublishedArticle[]
}

export function CoverEditorClient({ cover, publishedArticles = [] }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()

  // Form state
  const [title, setTitle] = useState(cover.title)
  const [dek, setDek] = useState(cover.dek ?? '')
  const [aspectRatio, setAspectRatio] = useState(cover.aspect_ratio)
  const [bgUrl, setBgUrl] = useState(cover.background_image_url)
  const [fallbackUrl, setFallbackUrl] = useState(cover.fallback_image_url ?? '')
  const [altText, setAltText] = useState(cover.alt_text ?? '')
  const [hotspots, setHotspots] = useState<MagazineHotspot[]>(cover.hotspots)
  const [layers, setLayers] = useState<MagazineMotionLayer[]>(cover.motion_layers)
  const [selectedHotspotId, setSelectedHotspotId] = useState<string | null>(null)
  const [saveError, setSaveError] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)
  const [uploading, setUploading] = useState(false)

  const selectedHotspot = hotspots.find((h) => h.id === selectedHotspotId) ?? null

  function handleHotspotUpdate(updated: MagazineHotspot) {
    setHotspots((prev) => prev.map((h) => (h.id === updated.id ? updated : h)))
  }

  function handleHotspotDelete(id: string) {
    setHotspots((prev) => prev.filter((h) => h.id !== id))
    setSelectedHotspotId(null)
  }

  async function handleImageUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (!file) return
    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const url = await uploadCoverImage(fd)
      setBgUrl(url)
    } catch (err) {
      setSaveError((err as Error).message)
    } finally {
      setUploading(false)
    }
  }

  function handleSave() {
    setSaveError(null)
    setSaved(false)
    startTransition(async () => {
      try {
        await saveCover(cover.id, {
          title,
          dek: dek || null,
          aspect_ratio: aspectRatio,
          background_image_url: bgUrl,
          fallback_image_url: fallbackUrl || null,
          alt_text: altText || null,
          hotspots,
          motion_layers: layers,
        })
        setSaved(true)
        setTimeout(() => setSaved(false), 3000)
      } catch (err) {
        setSaveError((err as Error).message)
      }
    })
  }

  return (
    <div className="flex flex-col h-full">
      {/* Top bar */}
      <div className="flex items-center justify-between px-6 py-4 border-b border-border flex-shrink-0">
        <div className="flex items-center gap-3">
          <Link
            href="/dashboard/magazine"
            className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
          >
            <ArrowLeft className="h-4 w-4 mr-1" />
            Covers
          </Link>
          <Separator orientation="vertical" className="h-5" />
          <h1 className="text-base font-semibold truncate max-w-xs">{title || 'Untitled'}</h1>
          {cover.active && (
            <span className="text-xs px-2 py-0.5 rounded-full bg-emerald-600/20 text-emerald-400 border border-emerald-600/30">
              Active
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {saved && <span className="text-xs text-emerald-400">Saved</span>}
          {saveError && <span className="text-xs text-destructive">{saveError}</span>}
          <Button onClick={handleSave} disabled={isPending} size="sm">
            <Save className="h-4 w-4 mr-2" />
            {isPending ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

      {/* Two-column body */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left — controls */}
        <div className="w-80 flex-shrink-0 overflow-y-auto border-r border-border px-5 py-6 space-y-6">
          {/* Basic fields */}
          <div className="space-y-4">
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Cover Details
            </p>

            <div className="space-y-1">
              <Label>Title</Label>
              <Input value={title} onChange={(e) => setTitle(e.target.value)} />
            </div>

            <div className="space-y-1">
              <Label>Dek (sub-headline)</Label>
              <Textarea
                value={dek}
                onChange={(e) => setDek(e.target.value)}
                rows={2}
                placeholder="Short editorial description"
              />
            </div>

            <div className="space-y-1">
              <Label>Aspect Ratio</Label>
              <Select value={aspectRatio} onValueChange={(v) => v && setAspectRatio(v)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {['3:4', '2:3', '4:5', '1:1'].map((r) => (
                    <SelectItem key={r} value={r}>
                      {r}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>

            <div className="space-y-1">
              <Label>Cover Image URL</Label>
              <div className="flex gap-2">
                <Input
                  value={bgUrl}
                  onChange={(e) => setBgUrl(e.target.value)}
                  placeholder="https://..."
                  className="flex-1 text-xs"
                />
                <label className="cursor-pointer">
                  <span
                    className={cn(
                      buttonVariants({ variant: 'outline', size: 'sm' }),
                      uploading && 'opacity-50 pointer-events-none',
                    )}
                  >
                    <Upload className="h-3 w-3" />
                  </span>
                  <input
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={handleImageUpload}
                  />
                </label>
              </div>
              {uploading && (
                <p className="text-xs text-muted-foreground">Uploading…</p>
              )}
            </div>

            <div className="space-y-1">
              <Label>Fallback Image URL</Label>
              <Input
                value={fallbackUrl}
                onChange={(e) => setFallbackUrl(e.target.value)}
                placeholder="https://... (optional)"
                className="text-xs"
              />
            </div>

            <div className="space-y-1">
              <Label>Alt Text</Label>
              <Input
                value={altText}
                onChange={(e) => setAltText(e.target.value)}
                placeholder="Accessibility description"
              />
            </div>
          </div>

          <Separator />

          {/* Hotspot list */}
          <div className="space-y-3">
            <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
              Hotspots ({hotspots.length})
            </p>
            <div className="space-y-1">
              {hotspots.map((h) => (
                <button
                  key={h.id}
                  onClick={() =>
                    setSelectedHotspotId((prev) =>
                      prev === h.id ? null : h.id,
                    )
                  }
                  className={`w-full text-left text-xs px-3 py-2 rounded-md border transition-colors ${
                    selectedHotspotId === h.id
                      ? 'border-cyan-500 bg-cyan-500/10 text-cyan-400'
                      : 'border-border hover:bg-accent'
                  }`}
                >
                  {h.title || h.id}
                </button>
              ))}
              {hotspots.length === 0 && (
                <p className="text-xs text-muted-foreground">
                  Click on the preview to add hotspots.
                </p>
              )}
            </div>

            <HotspotPanel
              hotspot={selectedHotspot}
              onUpdate={handleHotspotUpdate}
              onDelete={handleHotspotDelete}
              publishedArticles={publishedArticles}
            />
          </div>

          <Separator />

          {/* Motion layers */}
          <MotionLayerTable layers={layers} onChange={setLayers} />
        </div>

        {/* Right — visual editor */}
        <div className="flex-1 overflow-y-auto px-8 py-6">
          <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground mb-4">
            Visual Hotspot Editor
          </p>
          <HotspotEditor
            backgroundImageUrl={bgUrl}
            aspectRatio={aspectRatio}
            hotspots={hotspots}
            layers={layers}
            selectedId={selectedHotspotId}
            onSelect={setSelectedHotspotId}
            onChange={setHotspots}
          />
        </div>
      </div>
    </div>
  )
}
