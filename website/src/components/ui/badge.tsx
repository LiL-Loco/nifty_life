import { cva, type VariantProps } from 'class-variance-authority';

import { cn } from '@/lib/utils';

/**
 * A status pill.
 *
 * The four tones are the four APPLICATION STATUSES, not four colours. That is the
 * point of naming them this way: `under_review` being the accent colour is a
 * decision, and if the variant were called `info` the same colour would end up on
 * something merely informational. `submitted` gets its own name rather than
 * sharing `default`, because "neu" is a state a reviewer acts on, not the absence
 * of one — and `default` is then left to mean "a status this file has not been
 * told about", which should be visible rather than silently muted.
 */
const badgeVariants = cva(
  'inline-block rounded-full border px-2 py-[0.1rem] text-xs uppercase tracking-[0.04em]',
  {
    variants: {
      tone: {
        default: 'border-line text-muted',
        submitted: 'border-line text-muted',
        approved: 'border-ok text-ok',
        rejected: 'border-danger text-danger',
        under_review: 'border-accent text-accent',
      },
    },
    defaultVariants: { tone: 'default' },
  },
);

/** Accepts the database's status union directly, so a caller cannot pass a
 *  colour where it should have passed a state and get no compile error. */
export type PillTone = NonNullable<VariantProps<typeof badgeVariants>['tone']>;

export function StatusPill({
  className,
  tone,
  ...props
}: React.HTMLAttributes<HTMLSpanElement> & { tone?: PillTone }) {
  return <span className={cn(badgeVariants({ tone }), className)} {...props} />;
}