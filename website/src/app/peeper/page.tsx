import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import { peeperActor } from '@/lib/identity';
import { feed, replies } from '@/lib/peeper';
import { Composer, DeletePost, PostActions, StaffComposer } from './components';

export default async function PeeperPage() {
  const session = await currentSession();
  if (!session) redirect('/login');

  // One call decides whether this visitor writes as a character, as the team, or
  // cannot write at all. Three places each asking "am I staff / am I linked"
  // separately is how they drift apart.
  const actor = await peeperActor(session.discordId, session.username);
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

      {isStaff ? <StaffComposer name={session.username} /> : null}

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