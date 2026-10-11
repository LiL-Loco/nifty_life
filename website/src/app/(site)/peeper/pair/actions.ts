'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

import { requireSession } from '@/lib/auth';
import { requestPairing } from '@/lib/identity';

export async function pair(form: FormData): Promise<void> {
  const session = await requireSession();

  const code = String(form.get('code') ?? '').trim();

  const accepted = await requestPairing(session.discordId, code);
  if (!accepted) {
    redirect('/peeper/pair?error=bad-code');
  }

  // "Accepted" is not "confirmed". The game server has to hash the code and
  // write the link; we only ever hold a request.
  revalidatePath('/peeper/pair');
  redirect('/peeper/pair?sent=1');
}