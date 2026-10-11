import { cva, type VariantProps } from 'class-variance-authority';

import { cn } from '@/lib/utils';

/**
 * The notice.
 *
 * A left rule in a tone colour, no icon, no box. Three tones, and they are not
 * interchangeable: `error` and `ok` mean a thing happened, `default` is
 * informational. The original CSS used `.notice`, `.notice.error` and `.notice.ok`
 * — the same three, and the same names, so the migration is a rename rather than
 * a redesign.
 *
 * No `role="alert"` here on purpose for the `ok` tone. An announced success
 * interrupts a screen reader mid-sentence for information the person did not ask
 * for; errors do get `role="alert"` and are set at the call site, where the
 * author knows whether it is a live failure or a rendered one.
 */
const noticeVariants = cva(
  'mb-6 rounded-r-md border-l-[3px] border-l-accent bg-surface px-4 py-[0.85rem]',
  {
    variants: {
      tone: {
        info: '',
        error: 'border-l-danger',
        ok: 'border-l-ok',
      },
    },
    defaultVariants: { tone: 'info' },
  },
);

export function Notice({
  className,
  tone,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof noticeVariants>) {
  return <div className={cn(noticeVariants({ tone }), className)} {...props} />;
}