import { createAuthServerClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  const searchParams = new URL(request.url).searchParams
  const code = searchParams.get('code')

  // DEBUG: Log all headers to see what Azure is sending
  const proto = request.headers.get('x-forwarded-proto') || 'https'
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host') || 'localhost:3000'
  console.log('[callback] DEBUG - request.url:', request.url)
  console.log('[callback] DEBUG - x-forwarded-proto:', request.headers.get('x-forwarded-proto'))
  console.log('[callback] DEBUG - x-forwarded-host:', request.headers.get('x-forwarded-host'))
  console.log('[callback] DEBUG - host:', request.headers.get('host'))
  console.log('[callback] DEBUG - constructed baseUrl:', `${proto}://${host}`)

  const baseUrl = `${proto}://${host}`

  if (!code) {
    return NextResponse.redirect(`${baseUrl}/auth?error=no_code`)
  }

  const supabase = await createAuthServerClient()
  const { data, error } = await supabase.auth.exchangeCodeForSession(code)

  if (error || !data.session) {
    console.error('[auth/callback] session exchange failed:', error?.message)
    return NextResponse.redirect(`${baseUrl}/auth?error=session_failed`)
  }


  // Verify admin role via service role client (bypasses RLS)
  const admin = createAdminClient()
  const { data: profile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', data.session.user.id)
    .single()

  if (!profile || profile.role !== 'admin') {
    console.warn('[auth/callback] non-admin sign-in attempt:', data.session.user.email)
    await supabase.auth.signOut()
    return NextResponse.redirect(`${origin}/auth?error=unauthorized`)
  }

  return NextResponse.redirect(`${origin}/dashboard`)
}
