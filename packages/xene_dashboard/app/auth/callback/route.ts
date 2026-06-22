import { createAuthServerClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  const searchParams = new URL(request.url).searchParams
  const code = searchParams.get('code')

  // Construct baseUrl from x-forwarded headers (Azure Container Apps proxy headers)
  const proto = request.headers.get('x-forwarded-proto') || 'https'
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host') || 'localhost:3000'
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
    return NextResponse.redirect(`${baseUrl}/auth?error=unauthorized`)
  }

  return NextResponse.redirect(`${baseUrl}/dashboard`)
}
