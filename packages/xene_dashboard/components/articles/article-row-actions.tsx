'use client'

import { useTransition } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { Pencil } from 'lucide-react'
import { buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
import { deleteArticle, publishArticle, unpublishArticle } from '@/app/dashboard/articles/actions'

interface Props {
  id: string
  title: string
  status: string
}

export function ArticleRowActions({ id, title, status }: Props) {
  const [isPending, startTransition] = useTransition()
  const router = useRouter()

  function handleDelete() {
    if (!confirm(`Delete "${title}"?`)) return
    startTransition(async () => {
      await deleteArticle(id)
      router.refresh()
    })
  }

  function handlePublish() {
    startTransition(async () => {
      await publishArticle(id)
      router.refresh()
    })
  }

  function handleUnpublish() {
    startTransition(async () => {
      await unpublishArticle(id)
      router.refresh()
    })
  }

  return (
    <div className="flex items-center justify-end gap-2">
      {status === 'published' ? (
        <button
          onClick={handleUnpublish}
          disabled={isPending}
          className="text-xs text-muted-foreground hover:text-foreground transition-colors disabled:opacity-50"
        >
          Unpublish
        </button>
      ) : (
        <button
          onClick={handlePublish}
          disabled={isPending}
          className="text-xs text-emerald-400 hover:text-emerald-300 transition-colors disabled:opacity-50"
        >
          Publish
        </button>
      )}
      <button
        onClick={handleDelete}
        disabled={isPending}
        className="text-xs text-destructive hover:text-destructive/80 transition-colors disabled:opacity-50"
      >
        Delete
      </button>
      <Link
        href={`/dashboard/articles/${id}`}
        className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
      >
        <Pencil className="h-4 w-4" />
      </Link>
    </div>
  )
}
