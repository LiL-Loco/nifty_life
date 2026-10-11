import { cookies } from 'next/headers';
import { NextResponse } from 'next/server';

export async function GET(request: Request) {
  const store = await cookies();
  store.delete('nifty_session');
  store.delete('nifty_oauth_state');

  return NextResponse.redirect(new URL('/', request.url));
}