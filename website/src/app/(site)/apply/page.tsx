import { redirect } from 'next/navigation';

import { currentSession } from '@/lib/auth';
import ApplicationForm from './form';

export default async function ApplyPage() {
  const session = await currentSession();
  if (!session) redirect('/');

  return (
    <>
      <h1>Bewerbung</h1>
      <p className="lede">
        Angemeldet als <strong>{session.username}</strong>. Die Bewerbung läuft unter
        dieser Discord-Kennung - das ist die Identität, die der Server beim Verbinden
        prüft.
      </p>

      <ApplicationForm />
    </>
  );
}