'use client'

import { DetailedStatCard } from '@/components/shared/stat-card-detailed'
import {
  Users,
  BookImage,
  SlidersHorizontal,
  Mic2,
  Newspaper,
  FileText,
} from 'lucide-react'

interface OverviewCardsProps {
  userCount: number
  users: any[]
  activeCoverTitle: string
  presetCount: number
  presets: any[]
  artistCount: number
  artists: any[]
  articleCount: number
  articles: any[]
  pubCount: number
  publications: any[]
}

export function OverviewCards(props: OverviewCardsProps) {
  return (
    <div className="grid gap-4 grid-cols-2 lg:grid-cols-3">
      <DetailedStatCard
        title="Total Users"
        value={props.userCount}
        Icon={Users}
        description="Registered profiles"
        table="profiles"
        query=".select('id, email, username, role, created_at').order('created_at', desc).limit(10)"
        filters={{ count: props.userCount }}
        detailsContent={
          <div className="space-y-4">
            <div className="text-sm text-muted-foreground">Latest 10 users:</div>
            <div className="space-y-2 max-h-96 overflow-y-auto">
              {props.users.map((u: any) => (
                <div key={u.id} className="border border-border rounded p-2 text-xs space-y-1">
                  <div><span className="font-semibold">{u.email}</span> {u.role === 'admin' && <span className="text-purple-400">(admin)</span>}</div>
                  <div className="text-muted-foreground">{u.username || '—'}</div>
                  <div className="text-muted-foreground">{new Date(u.created_at).toLocaleString()}</div>
                </div>
              ))}
            </div>
          </div>
        }
      />
      <DetailedStatCard
        title="Active Cover"
        value={props.activeCoverTitle}
        Icon={BookImage}
        description="Current magazine issue"
        table="magazine_covers"
        filters={{ active: true }}
        detailsContent={
          <div className="text-sm text-muted-foreground">
            {props.activeCoverTitle === 'None' ? 'No active cover' : `Active: ${props.activeCoverTitle}`}
          </div>
        }
      />
      <DetailedStatCard
        title="Active Presets"
        value={props.presetCount}
        Icon={SlidersHorizontal}
        description="Enabled preset templates"
        table="preset_templates"
        query=".select('id, slug, name, enabled').eq('enabled', true).limit(10)"
        filters={{ enabled: true }}
        detailsContent={
          <div className="space-y-4">
            <div className="text-sm text-muted-foreground">Active presets (showing 10):</div>
            <div className="space-y-2 max-h-96 overflow-y-auto">
              {props.presets.map((p: any) => (
                <div key={p.id} className="border border-border rounded p-2 text-xs space-y-1">
                  <div><span className="font-semibold">{p.name}</span></div>
                  <div className="text-muted-foreground font-mono">{p.slug}</div>
                </div>
              ))}
            </div>
          </div>
        }
      />
      <DetailedStatCard
        title="Total Artists"
        value={props.artistCount}
        Icon={Mic2}
        description="In global artist database"
        table="artists"
        query=".select('id, name, entity_type').limit(10)"
        filters={{ total_count: props.artistCount }}
        detailsContent={
          <div className="space-y-4">
            <div className="text-sm text-muted-foreground">Sample artists (showing 10):</div>
            <div className="space-y-2 max-h-96 overflow-y-auto">
              {props.artists.map((a: any) => (
                <div key={a.id} className="border border-border rounded p-2 text-xs space-y-1">
                  <div><span className="font-semibold">{a.name}</span></div>
                  <div className="text-muted-foreground">{a.entity_type || 'artist'}</div>
                </div>
              ))}
            </div>
          </div>
        }
      />
      <DetailedStatCard
        title="Articles (7d)"
        value={props.articleCount}
        Icon={FileText}
        description="Discovered in last 7 days"
        table="artist_articles"
        query=".select('id, artist_name, title, discovered_at').gte('discovered_at', 7d-ago).order('discovered_at', desc).limit(10)"
        filters={{ discovered_last_7_days: true }}
        detailsContent={
          <div className="space-y-4">
            <div className="text-sm text-muted-foreground">Recent articles (showing 10):</div>
            <div className="space-y-2 max-h-96 overflow-y-auto">
              {props.articles.map((a: any) => (
                <div key={a.id} className="border border-border rounded p-2 text-xs space-y-1">
                  <div><span className="font-semibold">{a.title}</span></div>
                  <div className="text-muted-foreground">{a.artist_name} • {new Date(a.discovered_at).toLocaleDateString()}</div>
                </div>
              ))}
            </div>
          </div>
        }
      />
      <DetailedStatCard
        title="Active Publications"
        value={props.pubCount}
        Icon={Newspaper}
        description="RSS feeds being polled"
        table="press_publications"
        query=".select('id, name, enabled').eq('enabled', true).limit(10)"
        filters={{ enabled: true }}
        detailsContent={
          <div className="space-y-4">
            <div className="text-sm text-muted-foreground">Active publications (showing 10):</div>
            <div className="space-y-2 max-h-96 overflow-y-auto">
              {props.publications.map((p: any) => (
                <div key={p.id} className="border border-border rounded p-2 text-xs">
                  <span className="font-semibold">{p.name}</span>
                </div>
              ))}
            </div>
          </div>
        }
      />
    </div>
  )
}
