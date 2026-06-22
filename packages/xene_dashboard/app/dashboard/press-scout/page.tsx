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
