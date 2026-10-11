import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import ApplicationForm from './form';

export default async function ApplyPage() {
  const session = await currentSession();
  if (!session) redirect('/');

  return (
    <>
      <h1>Apply</h1>
      <p className="lede">
        Signed in as <strong>{session.username}</strong>. The application is filed
        under this Discord account — that is the identity the server checks when you
        connect.
      </p>

      <ApplicationForm />
    </>
  );
}