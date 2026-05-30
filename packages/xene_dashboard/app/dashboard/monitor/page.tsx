import { createAuthServerClient } from '@/lib/supabase/server'
import { MonitorClient } from '@/components/monitor/monitor-client'

export const dynamic = 'force-dynamic'

export default async function MonitorPage() {
  const supabase = await createAuthServerClient()
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? ''

  return (
    <div className="p-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold tracking-tight">Backend Monitor</h1>
        <p className="text-muted-foreground text-sm mt-1">
          Live stats from the Dart Frog backend. Requires backend to be running. Auto-refreshes every 15 seconds.
        </p>
      </div>
      <MonitorClient token={token} backendUrl={process.env.NEXT_PUBLIC_BACKEND_URL ?? ''} />
    </div>
  )
}
