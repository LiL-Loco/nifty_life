'use server';

import { revalidatePath } from 'next/cache';

import { currentAccount, requireAccount, type Account } from '@/lib/auth';
import type { DiscordLink } from '@/lib/users';
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
import { peeperActor } from '@/lib/identity';

export type ActionState = { error?: string; ok?: string } | undefined;

const NEEDS_DISCORD = 'Verknüpfe zuerst dein Discord-Konto auf der Kontoseite.';
const NEEDS_CHARACTER =
  'Verknüpfe zuerst deinen Charakter im Spiel, bevor du hier schreibst.';

/**
 * The Discord identity of the signed-in account, or the sentence that explains
 * its absence.
 *
 * Everything on this surface is keyed on the Discord ID — posts are authored by a
 * character bound to one, bans are per Discord ID, and staff is a Discord role.
 * An account without a link therefore cannot write anything here at all, and
 * saying which of the two missing links it is saves a support round.
 */
async function actorOrError() {
  const account = await requireAccount();
  if (!account.discord) return { error: NEEDS_DISCORD } as const;

  const actor = await peeperActor(account.discord.discordId, account.discord.username);
  return { account, actor } as const;
}

export async function publish(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const resolved = await actorOrError();
  if ('error' in resolved) return resolved;

  const result = await createPost(
    resolved.account.discord!.discordId,
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
  const resolved = await actorOrError();
  if ('error' in resolved) return resolved;
  const { actor } = resolved;

  const postId = String(form.get('post') ?? '');
  const liked = form.get('liked') === '1';

  if (actor.kind === 'staff') {
    if (liked) await staffUnlike(actor.discordId, postId);
    else await staffLike(actor.discordId, postId);
  } else if (actor.kind === 'character') {
    if (liked) await unlikePost(actor.characterId, postId);
    else await likePost(actor.characterId, postId);
  } else {
    return { error: NEEDS_CHARACTER };
  }

  revalidatePath('/peeper');
  return undefined;
}

export async function report(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const resolved = await actorOrError();
  if ('error' in resolved) return resolved;
  const { actor } = resolved;

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
        : ({ ok: false, error: NEEDS_CHARACTER } as const);

  if (!result.ok) return { error: result.error };

  revalidatePath('/peeper');
  return { ok: 'Gemeldet.' };
}

// ---------------------------------------------------------------------------
// Moderation team. Every action below re-checks staff on the PUBLIC connection
// before touching the admin one — deciding whether to trust the privileged
// connection must not itself require the privileged connection.
// ---------------------------------------------------------------------------

/**
 * Shared guard for the team actions.
 *
 * Staff is a Discord ROLE, so an account with no Discord link cannot be staff —
 * which makes `account.isStaff` false here rather than unknown. The check is on
 * the PUBLIC connection, exactly as in `requireStaffAccount`.
 *
 * The return type narrows `discord` to non-null, because the guard proves it and
 * every caller below would otherwise re-check a fact this function already
 * established.
 */
async function staffAccount(): Promise<
  | { error: 'Nicht autorisiert.' }
  | (Account & { discord: DiscordLink })
> {
  const account = await currentAccount();
  if (!account || !account.isStaff || !account.discord) {
    return { error: 'Nicht autorisiert.' };
  }
  return account as Account & { discord: DiscordLink };
}

/** Publish as the team. No character required. */
export async function staffPublish(
  _prev: ActionState,
  form: FormData,
): Promise<ActionState> {
  const account = await staffAccount();
  if ('error' in account) return account;

  const result = await staffPost(
    account.discord.discordId,
    account.discord.username,
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
  const account = await staffAccount();
  if ('error' in account) return account;

  const raw = form.get('reason');
  const result = await staffDeletePost(
    String(form.get('post') ?? ''),
    account.discord.discordId,
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
  const account = await staffAccount();
  if ('error' in account) return account;

  const postId = String(form.get('post') ?? '');
  if (form.get('liked') === '1') {
    await staffUnlike(account.discord.discordId, postId);
  } else {
    await staffLike(account.discord.discordId, postId);
  }

  revalidatePath('/peeper');
  return undefined;
}