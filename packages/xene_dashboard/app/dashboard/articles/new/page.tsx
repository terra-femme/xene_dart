'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createArticle } from '@/app/dashboard/articles/actions'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Button, buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { ArrowLeft, FileText, MessageSquare, Image, Mic } from 'lucide-react'
import Link from 'next/link'
import type { LayoutTemplate } from '@/lib/types/database'

const TEMPLATES: {
  value: LayoutTemplate
  label: string
  description: string
  Icon: React.ElementType
}[] = [
  {
    value: 'editorial',
    label: 'Editorial',
    description: 'Balanced columns — text + full-bleed images, magazine typography. Standard feature articles.',
    Icon: FileText,
  },
  {
    value: 'interview',
    label: 'Interview',
    description: 'Q&A rhythm — large pull quotes, voice notes prominent. For conversations.',
    Icon: MessageSquare,
  },
  {
    value: 'visual_essay',
    label: 'Visual Essay',
    description: 'Image/video blocks first, text is caption-weight. For photography and visual features.',
    Icon: Image,
  },
  {
    value: 'audio_story',
    label: 'Audio Story',
    description: 'Voice note player top, transcript as primary content, images inline. Audio-led stories.',
    Icon: Mic,
  },
]

function slugify(str: string): string {
  return str
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .trim()
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
}

export default function NewArticlePage() {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const [title, setTitle] = useState('')
  const [slug, setSlug] = useState('')
  const [slugEdited, setSlugEdited] = useState(false)
  const [dek, setDek] = useState('')
  const [author, setAuthor] = useState('')
  const [template, setTemplate] = useState<LayoutTemplate>('editorial')

  function handleTitleChange(value: string) {
    setTitle(value)
    if (!slugEdited) setSlug(slugify(value))
  }

  function handleCreate() {
    if (!title.trim()) {
      setError('Title is required.')
      return
    }
    if (!slug.trim()) {
      setError('Slug is required.')
      return
    }
    setError(null)

    startTransition(async () => {
      try {
        const id = await createArticle({
          title: title.trim(),
          slug: slug.trim(),
          layout_template: template,
          dek: dek.trim() || null,
          author: author.trim() || null,
          cover_image_url: null,
          theme_color: null,
        })
        router.push(`/dashboard/articles/${id}`)
      } catch (err) {
        setError((err as Error).message)
      }
    })
  }

  return (
    <div className="p-8 max-w-2xl">
      <div className="flex items-center gap-3 mb-6">
        <Link
          href="/dashboard/articles"
          className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          Articles
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>New Article</CardTitle>
          <CardDescription>
            Choose a layout template, then use the block builder to add content.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* Template picker */}
          <div className="space-y-2">
            <Label>Layout Template</Label>
            <div className="grid grid-cols-2 gap-3">
              {TEMPLATES.map(({ value, label, description, Icon }) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setTemplate(value)}
                  className={cn(
                    'flex flex-col items-start gap-2 rounded-lg border p-4 text-left transition-colors',
                    template === value
                      ? 'border-primary bg-primary/10'
                      : 'border-border hover:border-muted-foreground/50',
                  )}
                >
                  <div className="flex items-center gap-2">
                    <Icon className={cn('h-4 w-4', template === value ? 'text-primary' : 'text-muted-foreground')} />
                    <span className={cn('text-sm font-medium', template === value ? 'text-primary' : '')}>{label}</span>
                  </div>
                  <p className="text-xs text-muted-foreground leading-snug">{description}</p>
                </button>
              ))}
            </div>
          </div>

          {/* Title & slug */}
          <div className="space-y-1">
            <Label>Title *</Label>
            <Input
              value={title}
              onChange={(e) => handleTitleChange(e.target.value)}
              placeholder="The Sound of Displacement"
            />
          </div>

          <div className="space-y-1">
            <Label>Slug *</Label>
            <Input
              value={slug}
              onChange={(e) => {
                setSlug(e.target.value)
                setSlugEdited(true)
              }}
              placeholder="the-sound-of-displacement"
              className="font-mono text-xs"
            />
            <p className="text-xs text-muted-foreground">
              Used in hotspot links: <code className="bg-muted px-1 rounded">xene://article/{slug || '…'}</code>
            </p>
          </div>

          <div className="space-y-1">
            <Label>Dek</Label>
            <Textarea
              value={dek}
              onChange={(e) => setDek(e.target.value)}
              rows={2}
              placeholder="Short editorial description shown below the title"
            />
          </div>

          <div className="space-y-1">
            <Label>Author</Label>
            <Input
              value={author}
              onChange={(e) => setAuthor(e.target.value)}
              placeholder="Your name or pen name"
            />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <Button
            onClick={handleCreate}
            disabled={isPending}
            className="w-full"
          >
            {isPending ? 'Creating…' : 'Create Article'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
