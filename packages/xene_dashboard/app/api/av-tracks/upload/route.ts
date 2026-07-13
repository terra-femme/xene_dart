import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'
import { revalidatePath } from 'next/cache'
import { createAuthServerClient, createAdminClient } from '@/lib/supabase/server'
import { createAvTrackFromForm } from '@/lib/av-tracks'

// Bundle upload endpoint. A Route Handler (not a Server Action) because
// multi-file multipart bodies trip the server-action parser ("Unexpected end
// of form"); request.formData() here parses the same body fine and has no
// bodySizeLimit coupling.
//
// Auth: same admin gate as the dashboard layout / auth callback — a valid
// session cookie AND profiles.role === 'admin'.
export async function POST(request: NextRequest) {
  const supabase = await createAuthServerClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) {
    console.warn('[av-tracks/upload] rejected: no session')
    return NextResponse.json({ error: 'Not signed in' }, { status: 401 })
  }

  const admin = createAdminClient()
  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', user.id)
    .single()
  if (!profile || profile.role !== 'admin') {
    console.warn('[av-tracks/upload] rejected: not admin', user.email)
    return NextResponse.json({ error: 'Admin access required' }, { status: 403 })
  }

  try {
    const formData = await request.formData()
    console.log('[av-tracks/upload] received form with', [...formData.keys()].join(', '))
    const id = await createAvTrackFromForm(formData)
    revalidatePath('/dashboard/av-tracks')
    console.log('[av-tracks/upload] created track', id)
    return NextResponse.json({ id })
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Upload failed'
    console.error('[av-tracks/upload] failed:', message)
    return NextResponse.json({ error: message }, { status: 400 })
  }
}
