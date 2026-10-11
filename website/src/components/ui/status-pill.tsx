import { Badge } from './badge';
import type { ApplicationStatus } from '@/lib/applications';

/**
 * The application status as a Badge.
 *
 * The four statuses map to four visual weights, and that mapping is the whole
 * point of this wrapper — the Badge primitives are shadcn's, but the project
 * does not have a `submitted` variant and is not getting one. The shadcn
 * variants are design tokens, not application states.
 *
 * The success classes are the one project-specific colour that does not exist
 * in shadcn (`--color-success`, see globals.css). The Badge stays the
 * `outline` variant; only the colour changes.
 */

type Tone = ApplicationStatus | 'default';

const VARIANT: Record<Tone, 'default' | 'secondary' | 'destructive' | 'outline'> = {
  default: 'secondary',
  submitted: 'secondary',
  under_review: 'default',
  approved: 'outline',
  rejected: 'destructive',
};

const SUCCESS_CLASS = 'border-success/40 bg-success/10 text-success';

export function StatusPill({
  tone,
  className,
  children,
}: {
  tone: Tone;
  className?: string;
  children: React.ReactNode;
}) {
  const variant = VARIANT[tone];
  const colour = tone === 'approved' ? SUCCESS_CLASS : '';
  return (
    <Badge variant={variant} className={`${colour} ${className ?? ''}`.trim()}>
      {children}
    </Badge>
  );
}
