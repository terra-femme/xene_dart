'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createCover } from '@/app/dashboard/magazine/actions'
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
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { ArrowLeft } from 'lucide-react'
import Link from 'next/link'

export default function NewCoverPage() {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const [title, setTitle] = useState('')
  const [dek, setDek] = useState('')
  const [aspectRatio, setAspectRatio] = useState('3:4')
  const [bgUrl, setBgUrl] = useState('')
  const [fallbackUrl, setFallbackUrl] = useState('')
  const [altText, setAltText] = useState('')

  function handleCreate() {
    if (!title.trim() || !bgUrl.trim()) {
      setError('Title and Cover Image URL are required.')
      return
    }
    setError(null)
    startTransition(async () => {
      try {
        const id = await createCover({
          title: title.trim(),
          dek: dek.trim() || null,
          aspect_ratio: aspectRatio,
          background_image_url: bgUrl.trim(),
          fallback_image_url: fallbackUrl.trim() || null,
          alt_text: altText.trim() || null,
        })
        router.push(`/dashboard/magazine/${id}`)
      } catch (err) {
        setError((err as Error).message)
      }
    })
  }

  return (
    <div className="p-8 max-w-lg">
      <div className="flex items-center gap-3 mb-6">
        <Link
          href="/dashboard/magazine"
          className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
        >
          <ArrowLeft className="h-4 w-4 mr-1" />
          Covers
        </Link>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>New Magazine Cover</CardTitle>
          <CardDescription>
            Create the cover, then use the editor to add hotspots and motion
            layers.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="space-y-1">
            <Label>Title *</Label>
            <Input
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              placeholder="XENE Vol.01 No.01"
            />
          </div>

          <div className="space-y-1">
            <Label>Dek</Label>
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
            <Label>Cover Image URL *</Label>
            <Input
              value={bgUrl}
              onChange={(e) => setBgUrl(e.target.value)}
              placeholder="https://..."
            />
          </div>

          <div className="space-y-1">
            <Label>Fallback Image URL</Label>
            <Input
              value={fallbackUrl}
              onChange={(e) => setFallbackUrl(e.target.value)}
              placeholder="https://... (optional)"
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

          {error && <p className="text-sm text-destructive">{error}</p>}

          <Button
            onClick={handleCreate}
            disabled={isPending}
            className="w-full"
          >
            {isPending ? 'Creating…' : 'Create Cover'}
          </Button>
        </CardContent>
      </Card>
    </div>
  )
}
