'use server';

import { revalidatePath } from 'next/cache';

import { requireSession, currentSession } from '@/lib/auth';
import {
  createPost,
  likePost,
  reportPost,
  staffDeletePost,
  staffLike,
  staffPost,
  staffReport,
  staffUnlike,
  unlikePost,
} from '@/lib/peeper';
import { linkedCharacter, peeperActor, isStaff } from '@/lib/identity';

export type ActionState = { error?: string; ok?: string } | undefined;

/**
 * Resolve the session to the character it speaks as.
 *
 * Only the PLAYER path uses this. The team goes through `peeperActor` and the
 * admin connection, because a moderator has no character by design.
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
  return { ok: 'Beitrag veröffentlicht.' };
}

export async function toggleLike(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await requireSession();
  const actor = await peeperActor(session.discordId, session.username);

  const postId = String(form.get('post') ?? '');
  const liked = form.get('liked') === '1';

  if (actor.kind === 'staff') {
    if (liked) await staffUnlike(actor.discordId, postId);
    else await staffLike(actor.discordId, postId);
  } else if (actor.kind === 'character') {
    if (liked) await unlikePost(actor.characterId, postId);
    else await likePost(actor.characterId, postId);
  } else {
    return { error: 'Verknüpfe zuerst deinen Charakter im Spiel.' };
  }

  revalidatePath('/peeper');
  return undefined;
}

export async function report(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await requireSession();
  const actor = await peeperActor(session.discordId, session.username);

  // A moderator reports through the admin connection; a player through their
  // character. `peeperActor` resolves which, so this function does not care.
  const result =
    actor.kind === 'staff'
      ? await staffReport(
          actor.discordId,
          String(form.get('post') ?? ''),
          String(form.get('reason') ?? 'other'),
        )
      : actor.kind === 'character'
        ? await reportPost(
            actor.characterId,
            String(form.get('post') ?? ''),
            String(form.get('reason') ?? 'other'),
          )
        : ({ ok: false, error: 'Verknüpfe zuerst deinen Charakter im Spiel.' } as const);

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Gemeldet.' };
}

// ---------------------------------------------------------------------------
// Moderation team. Every action below re-checks staff on the PUBLIC connection
// before touching the admin one — deciding whether to trust the privileged
// connection must not itself require the privileged connection.
// ---------------------------------------------------------------------------

/** Shared guard. Returns the session or a ready-made error state. */
async function staffSession() {
  const session = await currentSession();
  if (!session || !(await isStaff(session.discordId))) {
    return { error: 'Nicht autorisiert.' } as const;
  }
  return session;
}

/** Publish as the team. No character required. */
export async function staffPublish(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await staffSession();
  if ('error' in session) return session;

  const result = await staffPost(
    session.discordId,
    session.username,
    String(form.get('body') ?? ''),
    form.get('place') ? String(form.get('place')) : null,
  );

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Beitrag veröffentlicht.' };
}

/**
 * Soft-delete a post.
 *
 * The reason is optional but worth taking: it is the only record of why
 * something disappeared, and without it the deletion is just a gap in a feed.
 */
export async function staffDelete(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await staffSession();
  if ('error' in session) return session;

  const raw = form.get('reason');
  const result = await staffDeletePost(
    String(form.get('post') ?? ''),
    session.discordId,
    typeof raw === 'string' && raw.trim() ? raw : null,
  );

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Beitrag gelöscht.' };
}

/** Like or unlike as the team. */
export async function staffToggleLike(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const session = await staffSession();
  if ('error' in session) return session;

  const postId = String(form.get('post') ?? '');
  if (form.get('liked') === '1') {
    await staffUnlike(session.discordId, postId);
  } else {
    await staffLike(session.discordId, postId);
  }

  revalidatePath('/peeper');
  return undefined;
}