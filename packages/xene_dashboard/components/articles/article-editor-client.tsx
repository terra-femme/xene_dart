'use client'

import { useState, useTransition, useRef } from 'react'
import { useRouter } from 'next/navigation'
import type {
  XeneArticle,
  ArticleBlock,
  BlockType,
  LayoutTemplate,
  ArticleStatus,
  TextBlock,
  QuoteBlock,
  ImageBlock,
  VideoBlock,
  VoiceNoteBlock,
  SpacerBlock,
} from '@/lib/types/database'
import { saveArticle, publishArticle, unpublishArticle, uploadArticleMedia } from '@/app/dashboard/articles/actions'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Button, buttonVariants } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'
import { cn } from '@/lib/utils'
import Link from 'next/link'
import {
  ArrowLeft,
  ArrowUp,
  ArrowDown,
  Trash2,
  Plus,
  Upload,
  FileText,
  Quote,
  Image,
  Video,
  Mic,
  Minus,
} from 'lucide-react'

const BLOCK_ICONS: Record<BlockType, React.ElementType> = {
  text: FileText,
  quote: Quote,
  image: Image,
  video: Video,
  voice_note: Mic,
  spacer: Minus,
}

const BLOCK_LABELS: Record<BlockType, string> = {
  text: 'Text',
  quote: 'Quote',
  image: 'Image',
  video: 'Video',
  voice_note: 'Voice Note',
  spacer: 'Spacer',
}

const TEMPLATE_LABELS: Record<LayoutTemplate, string> = {
  editorial: 'Editorial',
  interview: 'Interview',
  visual_essay: 'Visual Essay',
  audio_story: 'Audio Story',
}

function newBlock(type: BlockType): ArticleBlock {
  const id = Math.random().toString(36).slice(2, 9)
  switch (type) {
    case 'text':
      return { id, type, heading: null, body: '' }
    case 'quote':
      return { id, type, text: '', attribution: null }
    case 'image':
      return { id, type, url: '', caption: null, aspect: '16:9' }
    case 'video':
      return { id, type, url: '', thumbnail_url: null, provider: 'youtube' }
    case 'voice_note':
      return { id, type, url: '', duration_seconds: null, transcript: null }
    case 'spacer':
      return { id, type, size: 'md' }
  }
}

function blockPreview(block: ArticleBlock): string {
  switch (block.type) {
    case 'text':
      return block.heading ?? block.body.slice(0, 60) || '(empty)'
    case 'quote':
      return block.text.slice(0, 60) || '(empty)'
    case 'image':
      return block.caption ?? block.url.slice(0, 60) || '(no url)'
    case 'video':
      return block.url.slice(0, 60) || '(no url)'
    case 'voice_note':
      return block.transcript?.slice(0, 60) ?? block.url.slice(0, 60) || '(no url)'
    case 'spacer':
      return `Spacer — ${block.size}`
  }
}

// ─── Per-block editors ────────────────────────────────────────────────────────

function TextBlockEditor({
  block,
  onChange,
}: {
  block: TextBlock
  onChange: (b: TextBlock) => void
}) {
  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label>Heading (optional)</Label>
        <Input
          value={block.heading ?? ''}
          onChange={(e) => onChange({ ...block, heading: e.target.value || null })}
          placeholder="Section heading"
        />
      </div>
      <div className="space-y-1">
        <Label>Body *</Label>
        <Textarea
          value={block.body}
          onChange={(e) => onChange({ ...block, body: e.target.value })}
          placeholder="Paragraph text…"
          rows={6}
        />
      </div>
    </div>
  )
}

function QuoteBlockEditor({
  block,
  onChange,
}: {
  block: QuoteBlock
  onChange: (b: QuoteBlock) => void
}) {
  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label>Quote *</Label>
        <Textarea
          value={block.text}
          onChange={(e) => onChange({ ...block, text: e.target.value })}
          placeholder="The quote text…"
          rows={4}
        />
      </div>
      <div className="space-y-1">
        <Label>Attribution</Label>
        <Input
          value={block.attribution ?? ''}
          onChange={(e) => onChange({ ...block, attribution: e.target.value || null })}
          placeholder="Artist Name"
        />
      </div>
    </div>
  )
}

function ImageBlockEditor({
  block,
  onChange,
}: {
  block: ImageBlock
  onChange: (b: ImageBlock) => void
}) {
  const [uploading, setUploading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  async function handleUpload(file: File) {
    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const url = await uploadArticleMedia(fd)
      onChange({ ...block, url })
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label>Image URL *</Label>
        <div className="flex gap-2">
          <Input
            value={block.url}
            onChange={(e) => onChange({ ...block, url: e.target.value })}
            placeholder="https://…"
            className="flex-1"
          />
          <input
            ref={inputRef}
            type="file"
            accept="image/*"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) handleUpload(f)
            }}
          />
          <span
            onClick={() => inputRef.current?.click()}
            className={cn(
              buttonVariants({ variant: 'outline', size: 'sm' }),
              'cursor-pointer',
              uploading && 'opacity-50 pointer-events-none',
            )}
          >
            <Upload className="h-4 w-4" />
          </span>
        </div>
      </div>
      <div className="space-y-1">
        <Label>Aspect Ratio</Label>
        <Select
          value={block.aspect}
          onValueChange={(v) => v && onChange({ ...block, aspect: v as ImageBlock['aspect'] })}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {(['16:9', '4:3', '1:1', '3:4'] as const).map((r) => (
              <SelectItem key={r} value={r}>{r}</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label>Caption</Label>
        <Input
          value={block.caption ?? ''}
          onChange={(e) => onChange({ ...block, caption: e.target.value || null })}
          placeholder="Image caption"
        />
      </div>
      {block.url && (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={block.url} alt="preview" className="rounded border border-border max-h-48 object-contain" />
      )}
    </div>
  )
}

function VideoBlockEditor({
  block,
  onChange,
}: {
  block: VideoBlock
  onChange: (b: VideoBlock) => void
}) {
  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label>Video URL *</Label>
        <Input
          value={block.url}
          onChange={(e) => onChange({ ...block, url: e.target.value })}
          placeholder="https://youtube.com/watch?v=…"
        />
      </div>
      <div className="space-y-1">
        <Label>Provider</Label>
        <Select
          value={block.provider}
          onValueChange={(v) => v && onChange({ ...block, provider: v as VideoBlock['provider'] })}
        >
          <SelectTrigger>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="youtube">YouTube</SelectItem>
            <SelectItem value="direct">Direct URL</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <div className="space-y-1">
        <Label>Thumbnail URL</Label>
        <Input
          value={block.thumbnail_url ?? ''}
          onChange={(e) => onChange({ ...block, thumbnail_url: e.target.value || null })}
          placeholder="https://… (optional)"
        />
      </div>
    </div>
  )
}

function VoiceNoteBlockEditor({
  block,
  onChange,
}: {
  block: VoiceNoteBlock
  onChange: (b: VoiceNoteBlock) => void
}) {
  const [uploading, setUploading] = useState(false)
  const inputRef = useRef<HTMLInputElement>(null)

  async function handleUpload(file: File) {
    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const url = await uploadArticleMedia(fd)
      // Try to read duration from the audio file
      const duration = await getAudioDuration(file)
      onChange({ ...block, url, duration_seconds: duration })
    } finally {
      setUploading(false)
    }
  }

  return (
    <div className="space-y-3">
      <div className="space-y-1">
        <Label>Audio File *</Label>
        <div className="flex gap-2">
          <Input
            value={block.url}
            onChange={(e) => onChange({ ...block, url: e.target.value })}
            placeholder="https://… or upload below"
            className="flex-1"
          />
          <input
            ref={inputRef}
            type="file"
            accept="audio/*"
            className="hidden"
            onChange={(e) => {
              const f = e.target.files?.[0]
              if (f) handleUpload(f)
            }}
          />
          <span
            onClick={() => inputRef.current?.click()}
            className={cn(
              buttonVariants({ variant: 'outline', size: 'sm' }),
              'cursor-pointer',
              uploading && 'opacity-50 pointer-events-none',
            )}
          >
            <Upload className="h-4 w-4" />
            {uploading && <span className="ml-1 text-xs">…</span>}
          </span>
        </div>
      </div>
      <div className="space-y-1">
        <Label>Duration (seconds)</Label>
        <Input
          type="number"
          min="0"
          value={block.duration_seconds ?? ''}
          onChange={(e) => onChange({ ...block, duration_seconds: parseFloat(e.target.value) || null })}
          placeholder="45"
        />
        <p className="text-xs text-muted-foreground">Auto-filled on upload. Edit manually if needed.</p>
      </div>
      <div className="space-y-1">
        <Label>Transcript</Label>
        <Textarea
          value={block.transcript ?? ''}
          onChange={(e) => onChange({ ...block, transcript: e.target.value || null })}
          placeholder="Full transcript of the voice note…"
          rows={5}
        />
        <p className="text-xs text-muted-foreground">
          Displayed below the audio scrubber in the Flutter app. No waveform — just the transcript.
        </p>
      </div>
    </div>
  )
}

function SpacerBlockEditor({
  block,
  onChange,
}: {
  block: SpacerBlock
  onChange: (b: SpacerBlock) => void
}) {
  return (
    <div className="space-y-1">
      <Label>Size</Label>
      <Select
        value={block.size}
        onValueChange={(v) => v && onChange({ ...block, size: v as SpacerBlock['size'] })}
      >
        <SelectTrigger>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="sm">Small</SelectItem>
          <SelectItem value="md">Medium</SelectItem>
          <SelectItem value="lg">Large</SelectItem>
        </SelectContent>
      </Select>
    </div>
  )
}

function BlockEditor({
  block,
  onChange,
}: {
  block: ArticleBlock
  onChange: (b: ArticleBlock) => void
}) {
  switch (block.type) {
    case 'text':
      return <TextBlockEditor block={block} onChange={onChange} />
    case 'quote':
      return <QuoteBlockEditor block={block} onChange={onChange} />
    case 'image':
      return <ImageBlockEditor block={block} onChange={onChange} />
    case 'video':
      return <VideoBlockEditor block={block} onChange={onChange} />
    case 'voice_note':
      return <VoiceNoteBlockEditor block={block} onChange={onChange} />
    case 'spacer':
      return <SpacerBlockEditor block={block} onChange={onChange} />
  }
}

// Read audio duration from a File object (browser API)
function getAudioDuration(file: File): Promise<number | null> {
  return new Promise((resolve) => {
    const audio = new Audio()
    const url = URL.createObjectURL(file)
    audio.src = url
    audio.onloadedmetadata = () => {
      URL.revokeObjectURL(url)
      resolve(isFinite(audio.duration) ? Math.round(audio.duration) : null)
    }
    audio.onerror = () => {
      URL.revokeObjectURL(url)
      resolve(null)
    }
  })
}

// ─── Main editor ─────────────────────────────────────────────────────────────

interface Props {
  article: XeneArticle
}

const BLOCK_TYPES: BlockType[] = ['text', 'quote', 'image', 'video', 'voice_note', 'spacer']

export function ArticleEditorClient({ article }: Props) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState(false)

  // Metadata state
  const [title, setTitle] = useState(article.title)
  const [slug, setSlug] = useState(article.slug)
  const [dek, setDek] = useState(article.dek ?? '')
  const [author, setAuthor] = useState(article.author ?? '')
  const [template, setTemplate] = useState<LayoutTemplate>(article.layout_template)
  const [status, setStatus] = useState<ArticleStatus>(article.status)
  const [coverUrl, setCoverUrl] = useState(article.cover_image_url ?? '')
  const [themeColor, setThemeColor] = useState(article.theme_color ?? '')

  // Block state
  const [blocks, setBlocks] = useState<ArticleBlock[]>(article.blocks)
  const [selectedBlockId, setSelectedBlockId] = useState<string | null>(
    article.blocks[0]?.id ?? null,
  )

  const [showAddMenu, setShowAddMenu] = useState(false)

  const [coverUploading, setCoverUploading] = useState(false)
  const coverInputRef = useRef<HTMLInputElement>(null)

  const selectedBlock = blocks.find((b) => b.id === selectedBlockId) ?? null

  function updateBlock(updated: ArticleBlock) {
    setBlocks((prev) => prev.map((b) => (b.id === updated.id ? updated : b)))
  }

  function addBlock(type: BlockType) {
    const block = newBlock(type)
    setBlocks((prev) => [...prev, block])
    setSelectedBlockId(block.id)
    setShowAddMenu(false)
  }

  function removeBlock(id: string) {
    setBlocks((prev) => {
      const next = prev.filter((b) => b.id !== id)
      if (selectedBlockId === id) {
        setSelectedBlockId(next[0]?.id ?? null)
      }
      return next
    })
  }

  function moveBlock(id: string, dir: 'up' | 'down') {
    setBlocks((prev) => {
      const idx = prev.findIndex((b) => b.id === id)
      if (idx === -1) return prev
      const next = [...prev]
      const swapIdx = dir === 'up' ? idx - 1 : idx + 1
      if (swapIdx < 0 || swapIdx >= next.length) return prev
      ;[next[idx], next[swapIdx]] = [next[swapIdx], next[idx]]
      return next
    })
  }

  async function handleCoverUpload(file: File) {
    setCoverUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const url = await uploadArticleMedia(fd)
      setCoverUrl(url)
    } finally {
      setCoverUploading(false)
    }
  }

  function handleSave() {
    setError(null)
    setSuccess(false)
    startTransition(async () => {
      try {
        await saveArticle(article.id, {
          title: title.trim(),
          slug: slug.trim(),
          dek: dek.trim() || null,
          author: author.trim() || null,
          layout_template: template,
          cover_image_url: coverUrl.trim() || null,
          theme_color: themeColor.trim() || null,
          blocks,
        })
        setSuccess(true)
        setTimeout(() => setSuccess(false), 2000)
      } catch (err) {
        setError((err as Error).message)
      }
    })
  }

  function handlePublish() {
    startTransition(async () => {
      try {
        await publishArticle(article.id)
        setStatus('published')
      } catch (err) {
        setError((err as Error).message)
      }
    })
  }

  function handleUnpublish() {
    startTransition(async () => {
      try {
        await unpublishArticle(article.id)
        setStatus('draft')
      } catch (err) {
        setError((err as Error).message)
      }
    })
  }

  return (
    <div className="flex h-screen overflow-hidden flex-col">
      {/* Top bar */}
      <div className="flex items-center justify-between px-6 py-3 border-b border-border flex-shrink-0">
        <div className="flex items-center gap-3">
          <Link
            href="/dashboard/articles"
            className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
          >
            <ArrowLeft className="h-4 w-4 mr-1" />
            Articles
          </Link>
          <span className="text-sm font-medium truncate max-w-xs">{title || 'Untitled'}</span>
          <StatusBadge status={status} />
        </div>
        <div className="flex items-center gap-2">
          {error && <p className="text-xs text-destructive">{error}</p>}
          {success && <p className="text-xs text-emerald-400">Saved</p>}
          {status === 'published' ? (
            <Button variant="outline" size="sm" onClick={handleUnpublish} disabled={isPending}>
              Unpublish
            </Button>
          ) : (
            <Button variant="outline" size="sm" onClick={handlePublish} disabled={isPending}>
              Publish
            </Button>
          )}
          <Button size="sm" onClick={handleSave} disabled={isPending}>
            {isPending ? 'Saving…' : 'Save'}
          </Button>
        </div>
      </div>

      {/* Two-column body */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left panel: metadata + block list */}
        <div className="w-72 flex-shrink-0 border-r border-border overflow-y-auto">
          <div className="p-4 space-y-4">
            {/* Metadata */}
            <div className="space-y-3">
              <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                Metadata
              </p>

              <div className="space-y-1">
                <Label className="text-xs">Title</Label>
                <Input
                  value={title}
                  onChange={(e) => setTitle(e.target.value)}
                  className="h-8 text-xs"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Slug</Label>
                <Input
                  value={slug}
                  onChange={(e) => setSlug(e.target.value)}
                  className="h-8 text-xs font-mono"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Template</Label>
                <Select
                  value={template}
                  onValueChange={(v) => v && setTemplate(v as LayoutTemplate)}
                >
                  <SelectTrigger className="h-8 text-xs">
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {(Object.keys(TEMPLATE_LABELS) as LayoutTemplate[]).map((t) => (
                      <SelectItem key={t} value={t} className="text-xs">
                        {TEMPLATE_LABELS[t]}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Dek</Label>
                <Textarea
                  value={dek}
                  onChange={(e) => setDek(e.target.value)}
                  rows={2}
                  className="text-xs resize-none"
                  placeholder="Sub-headline"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Author</Label>
                <Input
                  value={author}
                  onChange={(e) => setAuthor(e.target.value)}
                  className="h-8 text-xs"
                />
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Cover Image URL</Label>
                <div className="flex gap-1">
                  <Input
                    value={coverUrl}
                    onChange={(e) => setCoverUrl(e.target.value)}
                    className="h-8 text-xs flex-1"
                    placeholder="https://…"
                  />
                  <input
                    ref={coverInputRef}
                    type="file"
                    accept="image/*"
                    className="hidden"
                    onChange={(e) => {
                      const f = e.target.files?.[0]
                      if (f) handleCoverUpload(f)
                    }}
                  />
                  <span
                    onClick={() => coverInputRef.current?.click()}
                    className={cn(
                      buttonVariants({ variant: 'outline', size: 'sm' }),
                      'cursor-pointer h-8 px-2',
                      coverUploading && 'opacity-50 pointer-events-none',
                    )}
                  >
                    <Upload className="h-3 w-3" />
                  </span>
                </div>
              </div>

              <div className="space-y-1">
                <Label className="text-xs">Theme Color</Label>
                <div className="flex gap-2 items-center">
                  <input
                    type="color"
                    value={themeColor || '#000000'}
                    onChange={(e) => setThemeColor(e.target.value)}
                    className="h-8 w-10 rounded border border-border bg-transparent cursor-pointer"
                  />
                  <Input
                    value={themeColor}
                    onChange={(e) => setThemeColor(e.target.value)}
                    className="h-8 text-xs font-mono flex-1"
                    placeholder="#00A88F"
                  />
                </div>
              </div>
            </div>

            <Separator />

            {/* Block list */}
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <p className="text-xs font-semibold uppercase tracking-widest text-muted-foreground">
                  Blocks ({blocks.length})
                </p>
                <div className="relative">
                  <Button
                    variant="outline"
                    size="sm"
                    className="h-7 text-xs"
                    onClick={() => setShowAddMenu((v) => !v)}
                  >
                    <Plus className="h-3 w-3 mr-1" />
                    Add
                  </Button>
                  {showAddMenu && (
                    <div className="absolute right-0 top-8 z-50 rounded-lg border border-border bg-card shadow-lg p-1 min-w-36">
                      {BLOCK_TYPES.map((type) => {
                        const Icon = BLOCK_ICONS[type]
                        return (
                          <button
                            key={type}
                            onClick={() => addBlock(type)}
                            className="flex items-center gap-2 w-full px-3 py-1.5 text-xs hover:bg-accent rounded-md transition-colors"
                          >
                            <Icon className="h-3 w-3 text-muted-foreground" />
                            {BLOCK_LABELS[type]}
                          </button>
                        )
                      })}
                    </div>
                  )}
                </div>
              </div>

              {blocks.length === 0 ? (
                <p className="text-xs text-muted-foreground py-2">
                  No blocks yet. Click Add to start.
                </p>
              ) : (
                <div className="space-y-1">
                  {blocks.map((block, idx) => {
                    const Icon = BLOCK_ICONS[block.type]
                    const isSelected = block.id === selectedBlockId
                    return (
                      <div
                        key={block.id}
                        onClick={() => setSelectedBlockId(block.id)}
                        className={cn(
                          'group flex items-start gap-2 rounded-md px-2 py-1.5 cursor-pointer transition-colors',
                          isSelected ? 'bg-accent' : 'hover:bg-accent/50',
                        )}
                      >
                        <Icon className="h-3.5 w-3.5 mt-0.5 flex-shrink-0 text-muted-foreground" />
                        <div className="flex-1 min-w-0">
                          <p className="text-xs font-medium">{BLOCK_LABELS[block.type]}</p>
                          <p className="text-xs text-muted-foreground truncate">
                            {blockPreview(block)}
                          </p>
                        </div>
                        <div className="flex flex-col gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity">
                          <button
                            onClick={(e) => { e.stopPropagation(); moveBlock(block.id, 'up') }}
                            disabled={idx === 0}
                            className="text-muted-foreground hover:text-foreground disabled:opacity-30"
                          >
                            <ArrowUp className="h-3 w-3" />
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); moveBlock(block.id, 'down') }}
                            disabled={idx === blocks.length - 1}
                            className="text-muted-foreground hover:text-foreground disabled:opacity-30"
                          >
                            <ArrowDown className="h-3 w-3" />
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); removeBlock(block.id) }}
                            className="text-destructive hover:text-destructive/80"
                          >
                            <Trash2 className="h-3 w-3" />
                          </button>
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          </div>
        </div>

        {/* Right panel: block editor */}
        <div className="flex-1 overflow-y-auto p-6">
          {selectedBlock ? (
            <div className="max-w-2xl space-y-4">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {(() => {
                    const Icon = BLOCK_ICONS[selectedBlock.type]
                    return <Icon className="h-4 w-4 text-muted-foreground" />
                  })()}
                  <p className="text-sm font-medium">{BLOCK_LABELS[selectedBlock.type]}</p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => removeBlock(selectedBlock.id)}
                  className="text-destructive hover:text-destructive"
                >
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
              <Separator />
              <BlockEditor
                block={selectedBlock}
                onChange={updateBlock}
              />
            </div>
          ) : (
            <div className="flex items-center justify-center h-full">
              <div className="text-center">
                <p className="text-sm text-muted-foreground">
                  Select a block from the left panel to edit it,
                </p>
                <p className="text-sm text-muted-foreground">
                  or click <strong>Add</strong> to create one.
                </p>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function StatusBadge({ status }: { status: ArticleStatus }) {
  if (status === 'published') {
    return (
      <Badge className="bg-emerald-600/20 text-emerald-400 border-emerald-600/30 text-xs">
        Published
      </Badge>
    )
  }
  if (status === 'scheduled') {
    return (
      <Badge className="bg-amber-600/20 text-amber-400 border-amber-600/30 text-xs">
        Scheduled
      </Badge>
    )
  }
  return (
    <Badge variant="outline" className="text-muted-foreground text-xs">
      Draft
    </Badge>
  )
}
