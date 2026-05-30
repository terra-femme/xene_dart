'use client'

import { useRef, useState } from 'react'
import type { MagazineMotionLayer } from '@/lib/types/database'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { Input } from '@/components/ui/input'
import { Button, buttonVariants } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Plus, Trash2, Upload } from 'lucide-react'
import { uploadMotionLayerFile } from '@/app/dashboard/magazine/actions'
import { cn } from '@/lib/utils'

interface Props {
  layers: MagazineMotionLayer[]
  onChange: (layers: MagazineMotionLayer[]) => void
}

function newLayer(): MagazineMotionLayer {
  return {
    id: Math.random().toString(36).slice(2, 9),
    type: 'lottie',
    url: '',
    x: 0,
    y: 0,
    width: 1,
    height: 1,
    loop: true,
    opacity: 1,
    speed: 1,
  }
}

export function MotionLayerTable({ layers, onChange }: Props) {
  const [uploadingId, setUploadingId] = useState<string | null>(null)
  const fileInputRefs = useRef<Record<string, HTMLInputElement | null>>({})

  function update<K extends keyof MagazineMotionLayer>(
    id: string,
    key: K,
    value: MagazineMotionLayer[K],
  ) {
    onChange(layers.map((l) => (l.id === id ? { ...l, [key]: value } : l)))
  }

  function remove(id: string) {
    onChange(layers.filter((l) => l.id !== id))
  }

  function add() {
    onChange([...layers, newLayer()])
  }

  async function handleFileUpload(id: string, file: File) {
    setUploadingId(id)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const url = await uploadMotionLayerFile(fd)
      update(id, 'url', url)
    } catch (err) {
      console.error('[MotionLayerTable] upload failed', err)
    } finally {
      setUploadingId(null)
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium">Motion Layers</p>
        <Button variant="outline" size="sm" onClick={add}>
          <Plus className="h-3 w-3 mr-1" />
          Add
        </Button>
      </div>

      {layers.length === 0 ? (
        <p className="text-xs text-muted-foreground py-2">
          No motion layers. Covers work fine without them.
        </p>
      ) : (
        <div className="space-y-3">
          {layers.map((l) => (
            <div
              key={l.id}
              className="rounded-lg border border-border p-3 space-y-2 bg-card"
            >
              {/* Row 1: Type + URL/Upload + Delete */}
              <div className="flex items-center gap-2">
                <Select
                  value={l.type}
                  onValueChange={(value) => value && update(l.id, 'type', value)}
                >
                  <SelectTrigger className="h-7 text-xs w-24 flex-shrink-0">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="lottie">Lottie</SelectItem>
                    <SelectItem value="shader">Shader</SelectItem>
                  </SelectContent>
                </Select>

                <div className="flex flex-1 gap-1 min-w-0">
                  <Input
                    value={l.url}
                    onChange={(e) => update(l.id, 'url', e.target.value)}
                    placeholder={
                      l.type === 'lottie'
                        ? 'https://… or upload .lottie / .json'
                        : 'intensity=1.0 #00A88F'
                    }
                    className="h-7 text-xs flex-1 min-w-0"
                  />
                  {l.type === 'lottie' && (
                    <>
                      <input
                        ref={(el) => { fileInputRefs.current[l.id] = el }}
                        type="file"
                        accept=".lottie,.json,application/json"
                        className="hidden"
                        onChange={(e) => {
                          const file = e.target.files?.[0]
                          if (file) handleFileUpload(l.id, file)
                        }}
                      />
                      <span
                        onClick={() => fileInputRefs.current[l.id]?.click()}
                        className={cn(
                          buttonVariants({ variant: 'outline', size: 'sm' }),
                          'h-7 px-2 cursor-pointer flex-shrink-0',
                          uploadingId === l.id && 'opacity-50 pointer-events-none',
                        )}
                        title="Upload .lottie or .json file"
                      >
                        <Upload className="h-3 w-3" />
                        {uploadingId === l.id && (
                          <span className="ml-1 text-xs">…</span>
                        )}
                      </span>
                    </>
                  )}
                </div>

                <Button
                  variant="ghost"
                  size="sm"
                  className="h-7 px-2 flex-shrink-0"
                  onClick={() => remove(l.id)}
                >
                  <Trash2 className="h-3 w-3 text-destructive" />
                </Button>
              </div>

              {/* Row 2: Position + Size + Opacity + Speed + Loop */}
              <div className="flex items-center gap-2 flex-wrap">
                {/* Position */}
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground w-3">X</span>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    max="1"
                    value={l.x.toFixed(2)}
                    onChange={(e) => update(l.id, 'x', parseFloat(e.target.value) || 0)}
                    className="h-7 text-xs w-14"
                  />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground w-3">Y</span>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    max="1"
                    value={l.y.toFixed(2)}
                    onChange={(e) => update(l.id, 'y', parseFloat(e.target.value) || 0)}
                    className="h-7 text-xs w-14"
                  />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground w-3">W</span>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    max="1"
                    value={l.width.toFixed(2)}
                    onChange={(e) => update(l.id, 'width', parseFloat(e.target.value) || 0)}
                    className="h-7 text-xs w-14"
                  />
                </div>
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground w-3">H</span>
                  <Input
                    type="number"
                    step="0.01"
                    min="0"
                    max="1"
                    value={l.height.toFixed(2)}
                    onChange={(e) => update(l.id, 'height', parseFloat(e.target.value) || 0)}
                    className="h-7 text-xs w-14"
                  />
                </div>

                <div className="w-px h-4 bg-border flex-shrink-0" />

                {/* Opacity */}
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground">Opacity</span>
                  <Input
                    type="number"
                    step="1"
                    min="0"
                    max="100"
                    value={Math.round((l.opacity ?? 1) * 100)}
                    onChange={(e) => {
                      const pct = Math.max(0, Math.min(100, parseInt(e.target.value) || 0))
                      update(l.id, 'opacity', pct / 100)
                    }}
                    className="h-7 text-xs w-14"
                  />
                  <span className="text-xs text-muted-foreground">%</span>
                </div>

                {/* Speed */}
                <div className="flex items-center gap-1">
                  <span className="text-xs text-muted-foreground">Speed</span>
                  <Input
                    type="number"
                    step="0.1"
                    min="0.1"
                    max="5"
                    value={(l.speed ?? 1).toFixed(1)}
                    onChange={(e) => {
                      const v = Math.max(0.1, Math.min(5, parseFloat(e.target.value) || 1))
                      update(l.id, 'speed', v)
                    }}
                    className="h-7 text-xs w-14"
                  />
                  <span className="text-xs text-muted-foreground">×</span>
                </div>

                <div className="w-px h-4 bg-border flex-shrink-0" />

                {/* Loop */}
                <div className="flex items-center gap-1.5">
                  <span className="text-xs text-muted-foreground">Loop</span>
                  <Switch
                    checked={l.loop}
                    onCheckedChange={(v) => update(l.id, 'loop', v)}
                  />
                </div>
              </div>

              {/* Uploaded file preview indicator */}
              {l.url && l.type === 'lottie' && (
                <p className="text-xs text-muted-foreground font-mono truncate">
                  {l.url}
                </p>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}
