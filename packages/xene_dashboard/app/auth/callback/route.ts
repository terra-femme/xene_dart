import { createAuthServerClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  console.log('[callback] === START ===')
  console.log('[callback] request.url:', request.url)
  console.log('[callback] headers: host=' + request.headers.get('host') + ' x-forwarded-proto=' + request.headers.get('x-forwarded-proto') + ' x-forwarded-host=' + request.headers.get('x-forwarded-host'))

  const { searchParams } = new URL(request.url)
  const code = searchParams.get('code')
  console.log('[callback] code:', code ? 'FOUND' : 'MISSING')

  if (!code) {
    console.log('[callback] redirecting to /auth?error=no_code')
    return NextResponse.redirect(`/auth?error=no_code`)
  }

  const supabase = await createAuthServerClient()
  const { data, error } = await supabase.auth.exchangeCodeForSession(code)

  if (error || !data.session) {
    console.error('[callback] session exchange FAILED:', error?.message)
    console.log('[callback] redirecting to /auth?error=session_failed')
    return NextResponse.redirect(`/auth?error=session_failed`)
  }

  console.log('[callback] SUCCESS - redirecting to /dashboard')


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
