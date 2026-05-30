'use client'

import { useRef, useState, useEffect, useCallback } from 'react'
import type { MagazineHotspot, MagazineMotionLayer } from '@/lib/types/database'

const EDITOR_WIDTH = 380

interface DragState {
  mode: 'move' | 'resize'
  hotspotId: string
  startX: number
  startY: number
  origX: number
  origY: number
  origW: number
  origH: number
}

interface HotspotEditorProps {
  backgroundImageUrl: string
  aspectRatio: string
  hotspots: MagazineHotspot[]
  layers?: MagazineMotionLayer[]
  selectedId: string | null
  onSelect: (id: string | null) => void
  onChange: (hotspots: MagazineHotspot[]) => void
}

function parseAspectRatio(ratio: string): number {
  const parts = ratio.split(':')
  if (parts.length !== 2) return 3 / 4
  const w = parseFloat(parts[0])
  const h = parseFloat(parts[1])
  return isNaN(w) || isNaN(h) || h === 0 ? 3 / 4 : w / h
}

function clamp(val: number, min = 0, max = 1) {
  return Math.max(min, Math.min(max, val))
}

function generateId() {
  return Math.random().toString(36).slice(2, 9)
}

export function HotspotEditor({
  backgroundImageUrl,
  aspectRatio,
  hotspots,
  layers = [],
  selectedId,
  onSelect,
  onChange,
}: HotspotEditorProps) {
  const containerRef = useRef<HTMLDivElement>(null)
  const [dragState, setDragState] = useState<DragState | null>(null)
  const [hoverPos, setHoverPos] = useState<{ x: number; y: number } | null>(null)

  const coverH = Math.round(EDITOR_WIDTH / parseAspectRatio(aspectRatio))

  const getContainerRect = useCallback(() => {
    return containerRef.current?.getBoundingClientRect() ?? {
      left: 0,
      top: 0,
      width: EDITOR_WIDTH,
      height: coverH,
    }
  }, [coverH])

  // Global mouse move + up for dragging
  useEffect(() => {
    if (!dragState) return

    function onMove(e: MouseEvent) {
      const rect = getContainerRect()
      const deltaX = (e.clientX - dragState!.startX) / rect.width
      const deltaY = (e.clientY - dragState!.startY) / rect.height

      onChange(
        hotspots.map((h) => {
          if (h.id !== dragState!.hotspotId) return h
          if (dragState!.mode === 'move') {
            return {
              ...h,
              x: clamp(dragState!.origX + deltaX),
              y: clamp(dragState!.origY + deltaY),
            }
          }
          // resize
          return {
            ...h,
            width: clamp(dragState!.origW + deltaX, 0.02, 1),
            height: clamp(dragState!.origH + deltaY, 0.02, 1),
          }
        }),
      )
    }

    function onUp() {
      setDragState(null)
    }

    document.addEventListener('mousemove', onMove)
    document.addEventListener('mouseup', onUp)
    return () => {
      document.removeEventListener('mousemove', onMove)
      document.removeEventListener('mouseup', onUp)
    }
  }, [dragState, hotspots, onChange, getContainerRect])

  function handleOverlayClick(e: React.MouseEvent<HTMLDivElement>) {
    // Only add a new hotspot when clicking the bare overlay (not a hotspot rect)
    if ((e.target as HTMLElement).dataset.role !== 'overlay') return
    const rect = containerRef.current!.getBoundingClientRect()
    const x = clamp((e.clientX - rect.left) / rect.width)
    const y = clamp((e.clientY - rect.top) / rect.height)
    const newHotspot: MagazineHotspot = {
      id: generateId(),
      x,
      y,
      width: 0.18,
      height: 0.08,
      title: 'New Hotspot',
      body: null,
      article_url: null,
    }
    const updated = [...hotspots, newHotspot]
    onChange(updated)
    onSelect(newHotspot.id)
  }

  function startDrag(
    e: React.MouseEvent,
    hotspot: MagazineHotspot,
    mode: 'move' | 'resize',
  ) {
    e.stopPropagation()
    e.preventDefault()
    setDragState({
      mode,
      hotspotId: hotspot.id,
      startX: e.clientX,
      startY: e.clientY,
      origX: hotspot.x,
      origY: hotspot.y,
      origW: hotspot.width,
      origH: hotspot.height,
    })
    onSelect(hotspot.id)
  }

  return (
    <div className="space-y-2">
      <p className="text-xs text-muted-foreground">
        Hover to preview placement and read coordinates. Click to add. Drag to move. Drag corner handle to resize.
      </p>
      <div
        ref={containerRef}
        style={{ width: EDITOR_WIDTH, height: coverH, position: 'relative' }}
        className="rounded-lg overflow-hidden border border-border bg-zinc-900 select-none"
        onMouseMove={(e) => {
          if (dragState) return
          const rect = containerRef.current?.getBoundingClientRect()
          if (!rect) return
          setHoverPos({
            x: Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width)),
            y: Math.max(0, Math.min(1, (e.clientY - rect.top) / rect.height)),
          })
        }}
        onMouseLeave={() => setHoverPos(null)}
      >
        {/* Cover image */}
        {backgroundImageUrl ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={backgroundImageUrl}
            alt="Cover preview"
            style={{ width: '100%', height: '100%', objectFit: 'contain', display: 'block' }}
            draggable={false}
          />
        ) : (
          <div className="w-full h-full flex items-center justify-center">
            <p className="text-xs text-muted-foreground">No image — enter a URL on the left</p>
          </div>
        )}

        {/* Clickable overlay for adding hotspots */}
        <div
          data-role="overlay"
          onClick={handleOverlayClick}
          style={{ position: 'absolute', inset: 0, cursor: 'crosshair' }}
        />

        {/* Hover crosshair + preview box — hidden during drag */}
        {hoverPos && !dragState && (
          <>
            {/* Ghost preview of the hotspot that would be created on click */}
            <div
              style={{
                position: 'absolute',
                left: hoverPos.x * EDITOR_WIDTH,
                top: hoverPos.y * coverH,
                width: 0.18 * EDITOR_WIDTH,
                height: 0.08 * coverH,
                background: 'rgba(234, 179, 8, 0.5)',
                border: '1px dashed rgba(234, 179, 8, 0.85)',
                pointerEvents: 'none',
                boxSizing: 'border-box',
              }}
            />
            {/* Horizontal hairline */}
            <div
              style={{
                position: 'absolute',
                top: hoverPos.y * coverH,
                left: 0,
                right: 0,
                height: 1,
                background: 'rgba(255,255,255,0.4)',
                pointerEvents: 'none',
                transform: 'translateY(-0.5px)',
              }}
            />
            {/* Vertical hairline */}
            <div
              style={{
                position: 'absolute',
                left: hoverPos.x * EDITOR_WIDTH,
                top: 0,
                bottom: 0,
                width: 1,
                background: 'rgba(255,255,255,0.4)',
                pointerEvents: 'none',
                transform: 'translateX(-0.5px)',
              }}
            />
            {/* Coordinate badge */}
            <div
              style={{
                position: 'absolute',
                bottom: 6,
                left: 6,
                background: 'rgba(0,0,0,0.75)',
                color: 'white',
                fontSize: 11,
                fontFamily: 'monospace',
                padding: '2px 6px',
                borderRadius: 4,
                pointerEvents: 'none',
                userSelect: 'none',
                letterSpacing: '0.02em',
              }}
            >
              x {hoverPos.x.toFixed(2)}  y {hoverPos.y.toFixed(2)}
            </div>
          </>
        )}

        {/* Motion layer overlays — non-interactive, render below hotspots */}
        {layers.map((l) => (
          <div
            key={l.id}
            style={{
              position: 'absolute',
              left: l.x * EDITOR_WIDTH,
              top: l.y * coverH,
              width: l.width * EDITOR_WIDTH,
              height: l.height * coverH,
              background: 'rgba(167, 139, 250, 0.25)',
              border: '1px dashed rgba(167, 139, 250, 0.7)',
              opacity: l.opacity,
              pointerEvents: 'none',
              boxSizing: 'border-box',
            }}
          >
            <span
              style={{
                position: 'absolute',
                top: 2,
                left: 4,
                fontSize: 9,
                color: 'rgba(196, 181, 253, 0.9)',
                whiteSpace: 'nowrap',
                overflow: 'hidden',
                maxWidth: '90%',
                textShadow: '0 0 4px rgba(0,0,0,0.9)',
                fontWeight: 600,
                pointerEvents: 'none',
              }}
            >
              {l.type}
            </span>
          </div>
        ))}

        {/* Rendered hotspots */}
        {hotspots.map((h) => {
          const isSelected = h.id === selectedId
          return (
            <div
              key={h.id}
              style={{
                position: 'absolute',
                left: h.x * EDITOR_WIDTH,
                top: h.y * coverH,
                width: h.width * EDITOR_WIDTH,
                height: h.height * coverH,
                border: `2px solid ${isSelected ? '#22d3ee' : '#facc15'}`,
                backgroundColor: isSelected
                  ? 'rgba(34,211,238,0.15)'
                  : 'rgba(250,204,21,0.12)',
                cursor: dragState?.hotspotId === h.id ? 'grabbing' : 'grab',
                boxSizing: 'border-box',
              }}
              onMouseDown={(e) => startDrag(e, h, 'move')}
            >
              {/* Label */}
              <span
                style={{
                  position: 'absolute',
                  top: 2,
                  left: 4,
                  fontSize: 9,
                  color: isSelected ? '#22d3ee' : '#facc15',
                  whiteSpace: 'nowrap',
                  overflow: 'hidden',
                  maxWidth: '90%',
                  pointerEvents: 'none',
                  textShadow: '0 0 4px rgba(0,0,0,0.9)',
                  fontWeight: 600,
                }}
              >
                {h.title}
              </span>

              {/* Resize handle — bottom-right corner */}
              <div
                style={{
                  position: 'absolute',
                  bottom: 0,
                  right: 0,
                  width: 12,
                  height: 12,
                  backgroundColor: isSelected ? '#22d3ee' : '#facc15',
                  cursor: 'se-resize',
                }}
                onMouseDown={(e) => startDrag(e, h, 'resize')}
              />
            </div>
          )
        })}
      </div>
    </div>
  )
}
