'use server';

import { revalidatePath } from 'next/cache';

import { requireSession } from '@/lib/auth';
import { submitApplication, validateAnswers } from '@/lib/applications';

export type ApplyState = { error?: string } | undefined;

/**
 * `useActionState` passes (previousState, formData) — in that order. Getting it
 * backwards type-checks only if the action is typed loosely, and then silently
 * receives the previous state as the form.
 */
export async function submit(
  _prev: ApplyState,
  form: FormData,
): Promise<ApplyState> {
  const session = await requireSession();

  const answers = validateAnswers(form);
  if (typeof answers === 'string') {
    return { error: answers };
  }

  const result = await submitApplication(session.discordId, answers);
  if (!result.ok) {
    return { error: result.error };
  }

  // The status page reads from the database, not from this form, so the redirect
  // shows what was actually stored rather than what was typed.
  revalidatePath('/status');
  return { error: undefined };
}