'use server';

import { revalidatePath } from 'next/cache';

import { requireAccount } from '@/lib/auth';
import { DISCORD_REQUIRED, submitApplication, validateAnswers } from '@/lib/applications';

export type ApplyState = { error?: string } | undefined;

/**
 * `useActionState` passes (previousState, formData) - in that order. Getting it
 * backwards type-checks only if the action is typed loosely, and then silently
 * receives the previous state as the form.
 */
export async function submit(
  _prev: ApplyState,
  form: FormData,
): Promise<ApplyState> {
  const account = await requireAccount();

  // Refused here as well as in `submitApplication`. The page hides the form in
  // this state, so a refusal reaching the action means somebody posted to it
  // directly — and a direct post must get the same sentence the page would have
  // given, not a stranger's error page.
  if (!account.discord) {
    return { error: DISCORD_REQUIRED };
  }

  const answers = validateAnswers(form);
  if (typeof answers === 'string') {
    return { error: answers };
  }

  const result = await submitApplication(account.user.id, account.discord.discordId, answers);
  if (!result.ok) {
    return { error: result.error };
  }

  // The status page reads from the database, not from this form, so the redirect
  // shows what was actually stored rather than what was typed.
  revalidatePath('/status');
  return { error: undefined };
}