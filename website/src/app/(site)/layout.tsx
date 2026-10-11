import { Footer } from '@/components/footer';
import { Navbar } from '@/components/navbar-server';
import { currentAccount } from '@/lib/auth';

/**
 * The portal's chrome — every page inside `app/(site)`.
 *
 * The navigation is ROLE-AWARE, and that is a reversal of an earlier decision
 * worth recording. The team link was removed from the public nav because a nav
 * entry a stranger can see but not click advertises a moderation area, and
 * because asking "is this person staff" on every page put a query in front of
 * every visitor on an otherwise public site.
 *
 * The owner then asked for the opposite thing in a specific form: the team must
 * NOT see links to Bewerbung and Status, and must get its own links instead. A
 * single navigation cannot do both without knowing who is looking, so this layout
 * now reads the account.
 *
 * The cost is one indexed lookup on `staff` for SIGNED-IN visitors only. An
 * anonymous visitor — every stranger, every search engine — pays nothing, because
 * `currentAccount()` returns on the cookie alone when there is no session to
 * decode. What it buys is that a moderator never sees a link to a form they are
 * not allowed to submit.
 */
export default async function SiteLayout({ children }: { children: React.ReactNode }) {
  const account = await currentAccount();

  return (
    <>
      <Navbar account={account} />
      <main>{children}</main>
      <Footer />
    </>
  );
}
