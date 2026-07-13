import Link from 'next/link'
import { redirect } from 'next/navigation'
import { createAuthServerClient, createAdminClient } from '@/lib/supabase/server'
import {
  LayoutDashboard,
  BookImage,
  FileText,
  Star,
  SlidersHorizontal,
  Mic2,
  Newspaper,
  BarChart3,
  Share2,
  Users,
  Gamepad2,
  Activity,
  LogOut,
  Search,
  AudioWaveform,
} from 'lucide-react'
import { Separator } from '@/components/ui/separator'

const navItems = [
  { href: '/dashboard', label: 'Overview', Icon: LayoutDashboard },
  { href: '/dashboard/magazine', label: 'Magazine Cover', Icon: BookImage },
  { href: '/dashboard/articles', label: 'Xene Articles', Icon: FileText },
  { href: '/dashboard/featured', label: 'Feature Strip', Icon: Star },
  { href: '/dashboard/presets', label: 'Presets', Icon: SlidersHorizontal },
  { href: '/dashboard/artists', label: 'Artists', Icon: Mic2 },
  { href: '/dashboard/publications', label: 'Publications', Icon: Newspaper },
  { href: '/dashboard/analytics', label: 'Analytics', Icon: BarChart3 },
  { href: '/dashboard/social', label: 'Social', Icon: Share2 },
  { href: '/dashboard/users', label: 'Users', Icon: Users },
  { href: '/dashboard/game', label: 'Game', Icon: Gamepad2 },
  { href: '/dashboard/av-tracks', label: 'AV Tracks', Icon: AudioWaveform },
  { href: '/dashboard/press-scout', label: 'Press Scout', Icon: Search },
  { href: '/dashboard/monitor', label: 'Monitor', Icon: Activity },
]

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const supabase = await createAuthServerClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) redirect('/auth')

  // Admin role check (service role bypasses RLS)
  const admin = createAdminClient()
  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()

  if (!profile || profile.role !== 'admin') redirect('/auth?error=unauthorized')

  return (
    <div className="flex h-screen overflow-hidden">
      {/* Sidebar */}
      <aside className="w-56 flex-shrink-0 flex flex-col border-r border-border bg-card">
        <div className="px-5 py-4">
          <p className="text-xs font-semibold tracking-widest uppercase text-muted-foreground">
            Xene
          </p>
          <p className="text-lg font-bold tracking-tight">Admin</p>
        </div>
        <Separator />
        <nav className="flex-1 overflow-y-auto px-2 py-3 space-y-0.5">
          {navItems.map(({ href, label, Icon }) => (
            <Link
              key={href}
              href={href}
              className="flex items-center gap-3 rounded-md px-3 py-2 text-sm text-muted-foreground hover:bg-accent hover:text-accent-foreground transition-colors"
            >
              <Icon className="h-4 w-4 flex-shrink-0" />
              {label}
            </Link>
          ))}
        </nav>
        <Separator />
        <div className="px-4 py-3">
          <div className="flex items-center gap-1.5 mb-2 min-w-0">
            <p className="text-xs text-muted-foreground truncate">
              {user.email}
            </p>
            <span className="flex-shrink-0 inline-flex items-center rounded-full bg-green-500/15 px-1.5 py-0.5 text-[10px] font-medium text-green-600 ring-1 ring-inset ring-green-500/20">
              admin
            </span>
          </div>
          <form action="/auth/signout" method="POST">
            <button
              type="submit"
              className="flex items-center gap-2 text-xs text-muted-foreground hover:text-foreground transition-colors"
            >
              <LogOut className="h-3 w-3" />
              Sign out
            </button>
          </form>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-y-auto">{children}</main>
    </div>
  )
}
