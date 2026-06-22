import { createAdminClient, createAuthServerClient } from '@/lib/supabase/server'
import { PressScoutClient } from '@/components/press-scout/press-scout-client'

export const dynamic = 'force-dynamic'

export default async function PressScoutPage() {
  const supabase = await createAuthServerClient()
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? ''

  const db = createAdminClient()

  const [{ data: articles }, { data: artists }, { data: presets }] = await Promise.all([
    db
      .from('artist_articles')
      .select(
        'id, artist_id, artist_name, title, url, snippet, source, published_at, discovered_at, preset_slug',
      )
      .order('discovered_at', { ascending: false })
      .limit(300),
    db
      .from('artists')
      .select('id, name, last_press_scout_at')
      .order('name', { ascending: true }),
    db
      .from('preset_templates')
      .select('id, slug, name')
      .eq('enabled', true)
      .order('name', { ascending: true }),
  ])

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Press Scout</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Gemini-powered editorial discovery. Auto-scouts every 12 hours; 60-day staleness window per artist.
        </p>
      </div>

      {/* Query Grounding */}
      <div className="rounded-lg border border-border bg-muted/30 p-4 space-y-3">
        <p className="text-xs font-semibold text-foreground">Data Sources</p>
        <div className="grid gap-3 grid-cols-2">
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Articles Table</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('artist_articles')
.select('...')
.order('discovered_at', desc)
.limit(300)
Total: ${articles?.length ?? 0}`}</pre>
          </div>
          <div className="space-y-1">
            <p className="text-xs text-muted-foreground">Artists Metadata</p>
            <pre className="text-xs bg-muted px-3 py-2 rounded overflow-x-auto font-mono text-muted-foreground">
{`.from('artists')
.select('id, name, last_press_scout_at')
.order('name', asc)
Total: ${artists?.length ?? 0} artists`}</pre>
          </div>
        </div>
      </div>

      <PressScoutClient
        token={token}
        backendUrl={process.env.NEXT_PUBLIC_BACKEND_URL ?? ''}
        initialArticles={articles ?? []}
        artistStatuses={artists ?? []}
        presets={presets ?? []}
      />
    </div>
  )
}
