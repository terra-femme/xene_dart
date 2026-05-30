'use client'

import { useState, useTransition } from 'react'
import Link from 'next/link'
import { Badge } from '@/components/ui/badge'
import { Button, buttonVariants } from '@/components/ui/button'
import { cn } from '@/lib/utils'
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
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { activateCover, deactivateCover, deleteCover } from '@/app/dashboard/magazine/actions'
import { Pencil, Trash2, CheckCircle, XCircle } from 'lucide-react'

interface Cover {
  id: string
  title: string
  aspect_ratio: string
  active: boolean
  published_at: string
  background_image_url: string
}

export function CoverListTable({ covers }: { covers: Cover[] }) {
  const [deleteTarget, setDeleteTarget] = useState<Cover | null>(null)
  const [isPending, startTransition] = useTransition()

  function handleActivate(id: string, currentlyActive: boolean) {
    startTransition(async () => {
      if (currentlyActive) {
        await deactivateCover(id)
      } else {
        await activateCover(id)
      }
    })
  }

  function handleDelete() {
    if (!deleteTarget) return
    startTransition(async () => {
      await deleteCover(deleteTarget.id)
      setDeleteTarget(null)
    })
  }

  return (
    <>
      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Title</TableHead>
              <TableHead>Ratio</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Published</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {covers.length === 0 && (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-muted-foreground py-12">
                  No covers yet. Click "New Cover" to create one.
                </TableCell>
              </TableRow>
            )}
            {covers.map((cover) => (
              <TableRow key={cover.id}>
                <TableCell className="font-medium">{cover.title}</TableCell>
                <TableCell className="text-muted-foreground">
                  {cover.aspect_ratio}
                </TableCell>
                <TableCell>
                  {cover.active ? (
                    <Badge className="bg-emerald-600/20 text-emerald-400 border-emerald-600/30">
                      Active
                    </Badge>
                  ) : (
                    <Badge variant="outline" className="text-muted-foreground">
                      Inactive
                    </Badge>
                  )}
                </TableCell>
                <TableCell className="text-muted-foreground text-sm">
                  {new Date(cover.published_at).toLocaleDateString()}
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex items-center justify-end gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => handleActivate(cover.id, cover.active)}
                      disabled={isPending}
                      title={cover.active ? 'Deactivate' : 'Activate'}
                    >
                      {cover.active ? (
                        <XCircle className="h-4 w-4 text-muted-foreground" />
                      ) : (
                        <CheckCircle className="h-4 w-4 text-emerald-500" />
                      )}
                    </Button>
                    <Link
                      href={`/dashboard/magazine/${cover.id}`}
                      className={cn(buttonVariants({ variant: 'ghost', size: 'sm' }))}
                    >
                      <Pencil className="h-4 w-4" />
                    </Link>
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => setDeleteTarget(cover)}
                      disabled={isPending}
                    >
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>

      <Dialog open={!!deleteTarget} onOpenChange={() => setDeleteTarget(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete cover?</DialogTitle>
            <DialogDescription>
              This will permanently delete "{deleteTarget?.title}". This cannot
              be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter>
            <Button variant="outline" onClick={() => setDeleteTarget(null)}>
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={handleDelete}
              disabled={isPending}
            >
              Delete
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </>
  )
}
