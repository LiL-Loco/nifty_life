'use server';

import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';

import { requireAccount } from '@/lib/auth';
import { requestPairing } from '@/lib/identity';

/**
 * Submit a character pairing code.
 *
 * The code was generated in game and typed here. We store it and nothing else —
 * there is no follow-up write, because we have no UPDATE. The game server picks
 * the request up when it runs and proves the code by hashing it.
 *
 * "Accepted" is not "confirmed". The game server has to hash the code and write
 * the link; we only ever hold a request.
 */
export async function pair(form: FormData): Promise<void> {
  const account = await requireAccount();

  if (!account.discord) {
    redirect('/account?error=link-needs-account');
  }

  const code = String(form.get('code') ?? '').trim();

  const accepted = await requestPairing(account.discord.discordId, code);
  if (!accepted) {
    redirect('/peeper/pair?error=bad-code');
  }

  revalidatePath('/peeper/pair');
  redirect('/peeper/pair?sent=1');
}