'use server';

import { revalidatePath } from 'next/cache';

import { requireSession } from '@/lib/auth';
import { createPost, likePost, reportPost, unlikePost } from '@/lib/peeper';
import { linkedCharacter } from '@/lib/identity';

export type ActionState = { error?: string; ok?: string } | undefined;

/**
 * Resolve the session to the character it speaks as.
 *
 * Every write needs this. A caller that is not linked gets a message rather than
 * an anonymous write — there is no "post as nobody" on this surface.
 */
async function actor() {
  const session = await requireSession();
  const link = await linkedCharacter(session.discordId);
  return link ? { characterId: link.characterId } : null;
}

export async function publish(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await requireSession();

  const result = await createPost(
    session.discordId,
    String(form.get('body') ?? ''),
    form.get('place') ? String(form.get('place')) : null,
    form.get('parent') ? String(form.get('parent')) : null,
  );

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Posted.' };
}

export async function toggleLike(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const who = await actor();
  if (!who) return { error: 'Link your character in game first.' };

  const postId = String(form.get('post') ?? '');
  const liked = form.get('liked') === '1';

  if (liked) {
    await unlikePost(who.characterId, postId);
  } else {
    await likePost(who.characterId, postId);
  }

  revalidatePath('/peeper');
  return undefined;
}

export async function report(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const who = await actor();
  if (!who) return { error: 'Link your character in game first.' };

  const result = await reportPost(
    who.characterId,
    String(form.get('post') ?? ''),
    String(form.get('reason') ?? 'other'),
  );

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Reported. Only staff can resolve a report.' };
}