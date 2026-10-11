import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentAccount } from '@/lib/auth';
import { discordConfigured } from '@/lib/config';
import { linkedCharacter, peeperActor } from '@/lib/identity';
import { feed, replies } from '@/lib/peeper';
import { Composer, DeletePost, PostActions, StaffComposer } from './components';

/**
 * The feed, and what this visitor may add to it.
 *
 * Three identities are possible and they are resolved in ONE place
 * (`peeperActor`), because the previous version asked the same question in the
 * page and in four actions separately and they drifted: staff is decided by a
 * Discord role, which means it is only decidable once a Discord account is
 * attached, and the page had no way to say that.
 */
export default async function PeeperPage() {
  const account = await currentAccount();
  if (!account) redirect('/login');

  if (!account.discord) {
    return (
      <>
        <h1>P&amp;R</h1>
        <div className="card">
          <p>
            P&amp;R wird von Charakteren geschrieben, und die Verbindung läuft über
            dein Discord-Konto. Ohne das verknüpfte Konto lässt sich hier nichts
            schreiben.
          </p>
          <p style={{ display: 'flex', gap: '0.75rem', flexWrap: 'wrap' }}>
            {discordConfigured ? (
              <Link className="button" href="/auth/discord/connect?next=/peeper">
                Discord-Konto verknüpfen
              </Link>
            ) : null}
            <Link className="button secondary" href="/account">
              Zur Kontoseite
            </Link>
          </p>
        </div>
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
      <h1>P&amp;R</h1>
      <p className="lede">
        Beiträge gehören Charakteren, nicht Konten — dieselbe Person im Spiel und
        hier, dieselbe Moderation auf beiden Seiten. Teambeiträge tragen stattdessen
        die Discord-Adresse, mit der sie geschrieben wurden.
      </p>

      {isStaff ? <StaffComposer name={discord.username} /> : null}

      {!link && !isStaff ? (
        <>
          <div className="notice">
            Dein Discord-Konto ist noch mit keinem Charakter verknüpft.{' '}
            <Link href="/peeper/pair">
              Erzeuge im Spiel einen Code und trage ihn hier ein
            </Link>
            .
          </div>

          <Composer disabled />
        </>
      ) : null}

      {link ? <Composer disabled={false} /> : null}

      {withReplies.length === 0 ? (
        <p className="muted">Es wurde noch nichts geschrieben.</p>
      ) : (
        withReplies.map(({ post, kids }) => (
          <article className="post" key={post.id}>
            <div className="post-head">
              <strong>{post.author_name}</strong>
              {post.source === 'staff' ? (
                <span
                  className="small"
                  style={{ color: 'var(--accent)', marginLeft: '0.4rem' }}
                >
                  Team
                </span>
              ) : null}
              <span className="muted">
                {post.created_at}
                {post.place_name ? ` · ${post.place_name}` : ''}
                {post.source === 'web' ? ' · web' : ''}
              </span>
            </div>

            <div className="post-body">{post.body}</div>

            {kids.length > 0 ? (
              <div
                style={{
                  marginTop: '0.75rem',
                  paddingLeft: '1rem',
                  borderLeft: '2px solid var(--line)',
                }}
              >
                {kids.map((kid) => (
                  <div key={kid.id} style={{ marginBottom: '0.5rem' }}>
                    <span className="muted small">
                      {kid.author_name} · {kid.created_at}
                    </span>
                    <div className="post-body small">{kid.body}</div>
                  </div>
                ))}
              </div>
            ) : null}

            <div style={{ display: 'flex', alignItems: 'flex-start', gap: '0.5rem' }}>
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