'use client'

import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog'
import { type LucideIcon, ChevronRight } from 'lucide-react'

interface DetailedStatCardProps {
  title: string
  value: string | number
  description?: string
  Icon: LucideIcon
  query?: string
  table?: string
  filters?: Record<string, string | number | boolean>
  onViewDetails?: () => Promise<void>
  detailsContent?: React.ReactNode
}

export function DetailedStatCard({
  title,
  value,
  description,
  Icon,
  query,
  table,
  filters,
  onViewDetails,
  detailsContent,
}: DetailedStatCardProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [isLoading, setIsLoading] = useState(false)

  const handleViewDetails = async () => {
    setIsOpen(true)
    if (onViewDetails) {
      setIsLoading(true)
      try {
        await onViewDetails()
      } finally {
        setIsLoading(false)
      }
    }
  }

  const hasDetails = onViewDetails || detailsContent

  return (
    <>
      <Card
        className={hasDetails ? 'cursor-pointer hover:bg-accent/50 transition-colors' : ''}
        onClick={hasDetails ? handleViewDetails : undefined}
      >
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <CardTitle className="text-sm font-medium text-muted-foreground">
            {title}
          </CardTitle>
          <div className="flex items-center gap-2">
            <Icon className="h-4 w-4 text-muted-foreground" />
            {hasDetails && <ChevronRight className="h-4 w-4 text-muted-foreground" />}
          </div>
        </CardHeader>
        <CardContent>
          <div className="text-2xl font-bold">{value}</div>
          {description && (
            <p className="text-xs text-muted-foreground mt-1">{description}</p>
          )}
          {hasDetails && (
            <p className="text-xs text-blue-400 mt-2 hover:text-blue-300">Click for details →</p>
          )}
        </CardContent>
      </Card>

      {hasDetails && (
        <Dialog open={isOpen} onOpenChange={setIsOpen}>
          <DialogContent className="max-w-2xl max-h-[80vh] overflow-y-auto">
            <DialogHeader>
              <DialogTitle>{title}</DialogTitle>
              {table && (
                <DialogDescription className="space-y-2 mt-2">
                  <div>
                    <span className="font-mono text-xs bg-muted px-2 py-1 rounded">
                      Table: {table}
                    </span>
                  </div>
                  {filters && Object.keys(filters).length > 0 && (
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-foreground">Filters:</p>
                      <div className="space-y-1">
                        {Object.entries(filters).map(([key, val]) => (
                          <div
                            key={key}
                            className="text-xs font-mono bg-muted px-2 py-1 rounded text-muted-foreground"
                          >
                            {key}: <span className="text-foreground">{JSON.stringify(val)}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                  {query && (
                    <div>
                      <p className="text-xs font-semibold text-foreground mb-1">Query:</p>
                      <pre className="text-xs bg-muted px-2 py-1.5 rounded overflow-x-auto font-mono text-muted-foreground">
                        {query}
                      </pre>
                    </div>
                  )}
                </DialogDescription>
              )}
            </DialogHeader>
            <div className="mt-4">
              {isLoading ? (
                <div className="text-center py-8 text-muted-foreground">Loading details...</div>
              ) : (
                detailsContent
              )}
            </div>
          </DialogContent>
        </Dialog>
      )}
    </>
  )
}
