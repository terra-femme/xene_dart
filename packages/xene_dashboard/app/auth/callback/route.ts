import { createAuthServerClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  console.log('[auth/callback] request.url:', request.url)
  console.log('[auth/callback] headers.host:', request.headers.get('host'))
  console.log('[auth/callback] headers.x-forwarded-for:', request.headers.get('x-forwarded-for'))
  console.log('[auth/callback] headers.x-forwarded-proto:', request.headers.get('x-forwarded-proto'))

  const { searchParams, origin } = new URL(request.url)
  console.log('[auth/callback] calculated origin:', origin)

  const code = searchParams.get('code')
  console.log('[auth/callback] code:', code ? 'present' : 'missing')

  if (!code) {
    return NextResponse.redirect(`${origin}/auth?error=no_code`)
  }

  const supabase = await createAuthServerClient()
  const { data, error } = await supabase.auth.exchangeCodeForSession(code)

  if (error || !data.session) {
    console.error('[auth/callback] session exchange failed:', error?.message)
    console.log('[auth/callback] redirecting to:', `${origin}/auth?error=session_failed`)
    return NextResponse.redirect(`${origin}/auth?error=session_failed`)
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
