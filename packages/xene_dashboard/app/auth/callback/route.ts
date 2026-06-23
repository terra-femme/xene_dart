import { createAuthServerClient } from '@/lib/supabase/server'
import { createAdminClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function GET(request: NextRequest) {
  console.log('═══════════════════════════════════════════════════════════')
  console.log('[CALLBACK] === START OF AUTH CALLBACK REQUEST ===')
  console.log('═══════════════════════════════════════════════════════════')

  // Log raw request URL
  console.log('[CALLBACK] Raw request.url:', request.url)

  // Log ALL headers
  console.log('[CALLBACK] ALL REQUEST HEADERS:')
  Array.from(request.headers.entries()).forEach(([key, value]) => {
    console.log(`  ${key}: ${value}`)
  })

  const searchParams = new URL(request.url).searchParams
  const code = searchParams.get('code')
  console.log('[CALLBACK] Code from searchParams:', code ? 'PRESENT' : 'MISSING')

  // Extract baseUrl from request URL origin (most reliable for Container Apps)
  const requestUrl = new URL(request.url)
  const baseUrl = `${requestUrl.protocol}//${requestUrl.host}`

  console.log('[CALLBACK] Request URL origin:', baseUrl)
  console.log('[CALLBACK] Full request URL:', request.url)
  console.log('[CALLBACK] Will redirect to:', code ? `${baseUrl}/dashboard` : `${baseUrl}/auth?error=no_code`)

  if (!code) {
    const errorUrl = `${baseUrl}/auth?error=no_code`
    console.error('[CALLBACK] REDIRECT: NO CODE FOUND ->', errorUrl)
    console.log('═══════════════════════════════════════════════════════════')
    return NextResponse.redirect(errorUrl)
  }

  console.log('[CALLBACK] Exchanging code for session...')
  const supabase = await createAuthServerClient()
  const { data, error } = await supabase.auth.exchangeCodeForSession(code)

  console.log('[CALLBACK] Session exchange result:')
  console.log(`  error: ${error?.message || 'NONE'}`)
  console.log(`  session exists: ${!!data.session}`)
  if (data.session) {
    console.log(`  user.id: ${data.session.user.id}`)
    console.log(`  user.email: ${data.session.user.email}`)
  }

  if (error || !data.session) {
    const errorUrl = `${baseUrl}/auth?error=session_failed`
    console.error('[CALLBACK] REDIRECT: SESSION EXCHANGE FAILED ->', errorUrl)
    console.error('[CALLBACK] Error details:', error?.message)
    console.log('═══════════════════════════════════════════════════════════')
    return NextResponse.redirect(errorUrl)
  }

  console.log('[CALLBACK] Checking admin role...')
  const admin = createAdminClient()
  const { data: profile, error: profileError } = await admin
    .from('profiles')
    .select('role')
    .eq('id', data.session.user.id)
    .single()

  console.log('[CALLBACK] Profile lookup result:')
  console.log(`  error: ${profileError?.message || 'NONE'}`)
  console.log(`  profile found: ${!!profile}`)
  if (profile) {
    console.log(`  role: ${profile.role}`)
  }

  if (!profile || profile.role !== 'admin') {
    const errorUrl = `${baseUrl}/auth?error=unauthorized`
    console.warn('[CALLBACK] REDIRECT: NOT ADMIN ->', errorUrl)
    console.warn('[CALLBACK] Email:', data.session.user.email)
    await supabase.auth.signOut()
    console.log('═══════════════════════════════════════════════════════════')
    return NextResponse.redirect(errorUrl)
  }

  const successUrl = `${baseUrl}/dashboard`
  console.log('[CALLBACK] REDIRECT: SUCCESS ->', successUrl)
  console.log('[CALLBACK] User:', data.session.user.email)
  console.log('═══════════════════════════════════════════════════════════')
  return NextResponse.redirect(successUrl)
}
