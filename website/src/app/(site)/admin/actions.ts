'use server';

import { revalidatePath } from 'next/cache';

/**
 * The approval action.
 *
 * It re-checks staff even though the layout already did: the layout check gates
 * rendering, this one gates the WRITE. They are minutes apart in the life of a
 * page and they answer different questions — "may this person see the queue"
 * and "may this person change this row".
 *
 * The status is checked against a fixed list here, not only in `decide()`. The
 * column grant already limits which columns can change; the list limits which
 * VALUES `status` may take, which a column grant cannot express.
 */
export async function decideAction(
  _previous: { ok: boolean; error?: string } | undefined,
  formData: FormData,
) {
  const { decide } = await import('@/lib/admin');
  const { currentAccount } = await import('@/lib/auth');

  const id = formData.get('id');
  const status = formData.get('status');
  const note = formData.get('note');

  if (typeof id !== 'string' || typeof status !== 'string') {
    return { ok: false as const, error: 'Unvollständige Anfrage.' };
  }

  if (
    status !== 'approved' &&
    status !== 'rejected' &&
    status !== 'under_review'
  ) {
    return { ok: false as const, error: 'Unbekannter Status.' };
  }

  // Decided on the PUBLIC connection, before the admin connection is ever
  // touched: whether to trust the privileged connection must not itself require
  // the privileged connection.
  const account = await currentAccount();
  if (!account || !account.isStaff) {
    return { ok: false as const, error: 'Nicht autorisiert.' };
  }

  const result = await decide(id, status, typeof note === 'string' ? note : null);

  if (result.ok) {
    revalidatePath('/admin');
    revalidatePath(`/admin/${id}`);
  }

  return result;
}