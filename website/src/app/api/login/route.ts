import { type NextRequest, NextResponse } from 'next/server';
import { cookies } from 'next/headers';
import { authenticate } from '@/lib/users';
import { cookieOptions, encodeSession, publicOrigin, SESSION_COOKIE } from '@/lib/session';

/**
 * POST /api/login
 *
 * A plain-old-form-submit route. The login form posts here instead of calling
 * the `'use server'` action directly, because that path goes through Next.js'
 * RSC stream encoding, which renders the Set-Cookie + Location headers
 * invisible to plain `curl -i` and has been the cause of every "the cookie
 * never appears in the response" debugging session on this project.
 *
 * A normal POST with a 303 redirect + a Set-Cookie on the response is exactly
 * what every browser, every curl, and every HTTP library expects, so we skip
 * the whole RSC dance for the login response.
 */
export async function POST(req: NextRequest): Promise<NextResponse> {
  const form = await req.formData();
  const email = String(form.get('email') ?? '');
  const password = String(form.get('password') ?? '');

  const result = await authenticate(email, password);
  if (!result.ok) {
    // Re-render the login page with the error inline. The simplest path is to
    // bounce back to /login with the error in the query string; the page reads
    // `?error=` and shows the message. Two round-trips; both cheap.
    const url = new URL('/login', publicOrigin(req));
    url.searchParams.set('error', 'bad_credentials');
    return NextResponse.redirect(url, { status: 303 });
  }

  const store = await cookies();
  store.set(
    SESSION_COOKIE,
    encodeSession({ userId: result.user.id, email: result.user.email }),
    cookieOptions(),
  );

  return NextResponse.redirect(`${publicOrigin(req)}/account`, { status: 303 });
}