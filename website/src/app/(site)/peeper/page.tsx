import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { linkedCharacter, peeperActor } from '@/lib/identity';
import { feed, replies } from '@/lib/peeper';
import { Alert, Card, buttonVariants } from '@/components/ui';
import { Composer, DeletePost, PostActions, StaffComposer } from './components';

/**
 * The feed, and what this visitor may add to it.
 *
 * Three identities are possible and they are resolved in ONE place
 * (`peeperActor`), because the previous version asked the same question in
 * the page and in four actions separately and they drifted: staff is decided
 * by a Discord role, which means it is only decidable once a Discord account
 * is attached, and the page had no way to say that.
 */
export default async function PeeperPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  if (!account.discord) {
    return (
      <>
        <h1>P&amp;R</h1>
        <Card>
          <p>
            P&amp;R wird von Charakteren geschrieben, und die Verbindung läuft über
            dein Discord-Konto. Ohne das verknüpfte Konto lässt sich hier nichts
            schreiben.
          </p>
          <p className="flex flex-wrap gap-3">
            {discordConfigured ? (
              <Link
                className={buttonVariants()}
                href="/auth/discord/connect?next=/peeper"
              >
                Discord-Konto verknüpfen
              </Link>
            ) : null}
            <Link className={buttonVariants({ variant: 'secondary' })} href="/account">
              Zur Kontoseite
            </Link>
          </p>
        </Card>
      </>
    );
  }

  const { discord } = account;

  // One call decides whether this visitor writes as a character, as the team, or
  // cannot write at all. Three places each asking "am I staff / am I linked"
  // separately is how they drift apart.
  const actor = await peeperActor(discord.discordId, discord.username);
  const isStaff = actor.kind === 'staff';
  const link = actor.kind === 'character' ? { characterId: actor.characterId } : null;

  const posts = await feed(30);

  // Replies are only fetched for posts that actually have some, so an untouched
  // feed costs one query rather than thirty.
  const withReplies = await Promise.all(
    posts.map(async (post) => ({
      post,
      kids: post.reply_count > 0 ? await replies(post.id) : [],
    })),
  );

  return (
    <>
      <h1 className="px-5 sm:px-6">P&amp;R</h1>
      <p className="mb-8 px-5 text-muted-foreground sm:px-6">
        Beiträge gehören Charakteren, nicht Konten — dieselbe Person im Spiel und
        hier, dieselbe Moderation auf beiden Seiten. Teambeiträge tragen stattdessen
        die Discord-Adresse, mit der sie geschrieben wurden.
      </p>

      {isStaff ? <StaffComposer name={discord.username} /> : null}

      {!link && !isStaff ? (
        <>
          <Alert>
            Dein Discord-Konto ist noch mit keinem Charakter verknüpft.{' '}
            <Link href="/peeper/pair">
              Erzeuge im Spiel einen Code und trage ihn hier ein
            </Link>
            .
          </Alert>

          <Composer disabled />
        </>
      ) : null}

      {link ? <Composer disabled={false} /> : null}

      {withReplies.length === 0 ? (
        <p className="text-muted-foreground">Es wurde noch nichts geschrieben.</p>
      ) : (
        withReplies.map(({ post, kids }) => (
          <article
            className="mb-[0.85rem] rounded-lg border border-border bg-card px-[1.1rem] py-4"
            key={post.id}
          >
            <div className="mb-1.5 flex justify-between gap-4 text-sm">
              <strong>{post.author_name}</strong>
              {post.source === 'staff' ? (
                <span className="ml-1.5 text-xs text-primary">Team</span>
              ) : null}
              <span className="text-muted-foreground">
                {post.created_at}
                {post.place_name ? ` · ${post.place_name}` : ''}
                {post.source === 'web' ? ' · web' : ''}
              </span>
            </div>

            <div className="overflow-wrap-anywhere whitespace-pre-wrap">{post.body}</div>

            {kids.length > 0 ? (
              <div className="mt-3 border-l-2 border-border pl-4">
                {kids.map((kid) => (
                  <div key={kid.id} className="mb-2">
                    <span className="text-sm text-muted-foreground">
                      {kid.author_name} · {kid.created_at}
                    </span>
                    <div className="overflow-wrap-anywhere whitespace-pre-wrap text-sm">
                      {kid.body}
                    </div>
                  </div>
                ))}
              </div>
            ) : null}

            <div className="flex items-start gap-2">
              <PostActions
                postId={post.id}
                likeCount={post.like_count}
                disabled={!link && !isStaff}
              />
              {isStaff ? (
                <DeletePost postId={post.id} authorName={post.author_name} />
              ) : null}
            </div>
          </article>
        ))
      )}
    </>
  );
}
