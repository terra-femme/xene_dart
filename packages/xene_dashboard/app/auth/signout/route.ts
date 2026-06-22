import { createAuthServerClient } from '@/lib/supabase/server'
import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export async function POST(request: NextRequest) {
  console.log('═══════════════════════════════════════════════════════════')
  console.log('[SIGNOUT] === START OF SIGNOUT REQUEST ===')

  const supabase = await createAuthServerClient()
  await supabase.auth.signOut()

  const proto = request.headers.get('x-forwarded-proto') || 'https'
  const host = request.headers.get('x-forwarded-host') || request.headers.get('host') || 'localhost:3000'
  const baseUrl = `${proto}://${host}`

  console.log('[SIGNOUT] Constructed baseUrl:', baseUrl)

  const redirectUrl = `${baseUrl}/auth`
  console.log('[SIGNOUT] REDIRECT:', redirectUrl)
  console.log('═══════════════════════════════════════════════════════════')

  return NextResponse.redirect(redirectUrl)
}
