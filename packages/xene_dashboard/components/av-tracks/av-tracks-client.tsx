'use client'

import { useRef, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createAvTrack, deleteAvTrack, moveAvTrack, type AvTrackRow } from '@/app/dashboard/av-tracks/actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Badge } from '@/components/ui/badge'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { ArrowDown, ArrowUp, Trash2, Upload } from 'lucide-react'

const SLOT_KEYS = ['original', 'vocals', 'drums', 'bass', 'other'] as const
type SlotKey = (typeof SLOT_KEYS)[number]

/** Filename (master.mp3, vocals.mp3, ...) -> slot key. Mirrors the lab exporter. */
function classifySlot(name: string): SlotKey | null {
  const base = name.toLowerCase().replace(/\.[^.]+$/, '')
  if (base.includes('master') || base.includes('original')) return 'original'
  if (base.includes('vocal')) return 'vocals'
  if (base.includes('drum')) return 'drums'
  if (base.includes('bass')) return 'bass'
  if (base.includes('other')) return 'other'
  return null
}

interface PendingBundle {
  manifest: string
  title: string
  audio: Partial<Record<SlotKey, File>>
  chart: File | null
}

export function AvTracksClient({ tracks }: { tracks: AvTrackRow[] }) {
  const router = useRouter()
  const [isPending, startTransition] = useTransition()
  const [bundle, setBundle] = useState<PendingBundle | null>(null)
  const [artist, setArtist] = useState('')
  const [status, setStatus] = useState<string | null>(null)
  const fileInput = useRef<HTMLInputElement>(null)

  async function onFilesPicked(list: FileList | null) {
    setStatus(null)
    if (!list || list.length === 0) return
    const files = [...list]
    console.log('[av-tracks] picked', files.map((f) => f.name))

    // two JSONs travel in a bundle: track.json (manifest) and chart.json (optional)
    const jsonFiles = files.filter((f) => f.name.toLowerCase().endsWith('.json'))
    const manifestFile = jsonFiles.find((f) => !f.name.toLowerCase().includes('chart'))
    const chartFile = jsonFiles.find((f) => f.name.toLowerCase().includes('chart')) ?? null
    if (!manifestFile) {
      setStatus('Include track.json from the lab export (plus the transcoded audio files).')
      return
    }
    const manifest = await manifestFile.text()
    let title = 'Untitled'
    try {
      const parsed = JSON.parse(manifest)
      if (parsed.version !== 1) {
        setStatus(`Unsupported track.json version: ${parsed.version}`)
        return
      }
      title = parsed.title || title
    } catch {
      setStatus('track.json is not valid JSON.')
      return
    }

    const audio: Partial<Record<SlotKey, File>> = {}
    for (const f of files) {
      if (f === manifestFile || f === chartFile) continue
      const slot = classifySlot(f.name)
      if (slot) audio[slot] = f
      else console.warn('[av-tracks] unrecognised file skipped', f.name)
    }
    if (!audio.original) {
      setStatus('Missing the master/original audio file — it is the only audible one.')
      return
    }
    setBundle({ manifest, title, audio, chart: chartFile })
  }

  function submit() {
    if (!bundle) return
    const fd = new FormData()
    fd.set('manifest', bundle.manifest)
    fd.set('artist', artist)
    for (const slot of SLOT_KEYS) {
      const f = bundle.audio[slot]
      if (f) fd.set(`audio_${slot}`, f)
    }
    if (bundle.chart) fd.set('chart', bundle.chart)
    startTransition(async () => {
      try {
        const id = await createAvTrack(fd)
        console.log('[av-tracks] created', id)
        setStatus(`Uploaded "${bundle.title}".`)
        setBundle(null)
        setArtist('')
        if (fileInput.current) fileInput.current.value = ''
        router.refresh()
      } catch (err) {
        console.error('[av-tracks] create failed', err)
        setStatus(err instanceof Error ? err.message : 'Upload failed.')
      }
    })
  }

  function remove(id: string, title: string) {
    if (!window.confirm(`Delete "${title}"? This removes its audio from storage too.`)) return
    startTransition(async () => {
      try {
        await deleteAvTrack(id)
        router.refresh()
      } catch (err) {
        console.error('[av-tracks] delete failed', err)
        setStatus(err instanceof Error ? err.message : 'Delete failed.')
      }
    })
  }

  function move(id: string, direction: -1 | 1) {
    startTransition(async () => {
      try {
        await moveAvTrack(id, direction)
        router.refresh()
      } catch (err) {
        console.error('[av-tracks] move failed', err)
        setStatus(err instanceof Error ? err.message : 'Reorder failed.')
      }
    })
  }

  return (
    <div className="space-y-6">
      {/* upload */}
      <div className="rounded-lg border border-border p-4 space-y-3">
        <p className="text-sm font-semibold">Add track</p>
        <p className="text-xs text-muted-foreground">
          Select the files from a lab export bundle: <span className="font-mono">track.json</span> plus the
          transcoded audio (<span className="font-mono">master.mp3</span>, <span className="font-mono">vocals.mp3</span>, …).
        </p>
        <input
          ref={fileInput}
          type="file"
          multiple
          accept=".json,.mp3,.m4a,.wav"
          onChange={(e) => onFilesPicked(e.target.files)}
          className="block text-xs text-muted-foreground file:mr-3 file:rounded-md file:border file:border-border file:bg-muted file:px-3 file:py-1.5 file:text-xs file:text-foreground"
        />
        {bundle && (
          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-1.5">
              <span className="text-sm">{bundle.title}</span>
              {SLOT_KEYS.filter((s) => bundle.audio[s]).map((s) => (
                <Badge key={s} variant="outline" className="text-xs">{s}</Badge>
              ))}
              {bundle.chart && <Badge className="text-xs">chart</Badge>}
            </div>
            <div className="flex items-center gap-2">
              <Input
                value={artist}
                onChange={(e) => setArtist(e.target.value)}
                placeholder="artist (optional)"
                className="h-8 max-w-56 text-xs"
              />
              <Button size="sm" onClick={submit} disabled={isPending}>
                <Upload className="h-4 w-4 mr-1" />
                {isPending ? 'Uploading…' : 'Upload to playlist'}
              </Button>
            </div>
          </div>
        )}
        {status && <p className="text-xs text-muted-foreground">{status}</p>}
      </div>

      {/* playlist */}
      <div className="rounded-lg border border-border overflow-hidden">
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-12">#</TableHead>
              <TableHead>Title</TableHead>
              <TableHead>Artist</TableHead>
              <TableHead>Crop</TableHead>
              <TableHead>Stems</TableHead>
              <TableHead className="text-right">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {tracks.length === 0 && (
              <TableRow>
                <TableCell colSpan={6} className="text-center text-sm text-muted-foreground py-8">
                  No tracks yet — export a bundle from the AV lab and upload it here.
                </TableCell>
              </TableRow>
            )}
            {tracks.map((t, i) => (
              <TableRow key={t.id}>
                <TableCell className="text-muted-foreground">{i + 1}</TableCell>
                <TableCell>{t.title}</TableCell>
                <TableCell className="text-muted-foreground">{t.artist ?? '—'}</TableCell>
                <TableCell className="font-mono text-xs text-muted-foreground">
                  {Number(t.crop_start_s).toFixed(1)}s + {Number(t.duration_s).toFixed(0)}s
                </TableCell>
                <TableCell>
                  <div className="flex gap-1 flex-wrap">
                    {Object.keys(t.files ?? {}).map((slot) => (
                      <Badge key={slot} variant="outline" className="text-xs">{slot}</Badge>
                    ))}
                  </div>
                </TableCell>
                <TableCell className="text-right">
                  <div className="flex justify-end gap-1">
                    <Button variant="ghost" size="sm" disabled={isPending || i === 0} onClick={() => move(t.id, -1)}>
                      <ArrowUp className="h-4 w-4" />
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={isPending || i === tracks.length - 1}
                      onClick={() => move(t.id, 1)}
                    >
                      <ArrowDown className="h-4 w-4" />
                    </Button>
                    <Button variant="ghost" size="sm" disabled={isPending} onClick={() => remove(t.id, t.title)}>
                      <Trash2 className="h-4 w-4 text-destructive" />
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
    </div>
  )
}
