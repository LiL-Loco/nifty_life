import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

import { SESSION_COOKIE } from '@/lib/session';

export async function GET(request: Request) {
  const store = await cookies();
  store.delete(SESSION_COOKIE);
  store.delete('nifty_oauth_state');

  return NextResponse.redirect(new URL('/logout/done', request.url));
}
