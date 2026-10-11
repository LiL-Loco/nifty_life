import Link from 'next/link';
import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import { linkedCharacter } from '@/lib/identity';
import { feed, replies } from '@/lib/peeper';
import { Composer, PostActions } from './components';

export default async function PeeperPage() {
  const session = await currentSession();
  if (!session) redirect('/');

  const link = await linkedCharacter(session.discordId);
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
      <h1>Peeper</h1>
      <p className="lede">
        Beiträge gehören Charakteren, nicht Konten - dieselbe Person im Spiel und
        hier, dieselbe Moderation auf beiden Seiten.
      </p>

      {!link ? (
        <div className="notice">
          Dein Discord-Konto ist noch mit keinem Charakter verknüpft.{' '}
          <Link href="/peeper/pair">
            Erzeuge im Spiel einen Code und trage ihn hier ein
          </Link>
          .
        </div>
      ) : null}

      <Composer disabled={!link} />

      {withReplies.length === 0 ? (
        <p className="muted">Es wurde noch nichts geschrieben.</p>
      ) : (
        withReplies.map(({ post, kids }) => (
          <article className="post" key={post.id}>
            <div className="post-head">
              <strong>{post.author_name}</strong>
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

            <PostActions postId={post.id} likeCount={post.like_count} disabled={!link} />
          </article>
        ))
      )}
    </>
  );
}