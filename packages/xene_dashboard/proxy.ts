import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function proxy(request: NextRequest) {
  let response = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          )
          response = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          )
        },
      },
    },
  )

  const {
    data: { user },
  } = await supabase.auth.getUser()

  // Unauthenticated user trying to reach dashboard → send to login
  if (request.nextUrl.pathname.startsWith('/dashboard') && !user) {
    return NextResponse.redirect(new URL('/auth', request.url))
  }

  // Authenticated user visiting /auth with no ?error → skip to dashboard
  // Don't redirect when ?error= is present — that's an intentional landing (e.g. unauthorized)
  if (
    request.nextUrl.pathname === '/auth' &&
    !request.nextUrl.searchParams.get('error') &&
    user
  ) {
    return NextResponse.redirect(new URL('/dashboard', request.url))
  }

  return response
}

export const config = {
  // Do NOT include /auth/callback — the Route Handler manages its own session cookies
  matcher: ['/dashboard/:path*', '/auth'],
}
