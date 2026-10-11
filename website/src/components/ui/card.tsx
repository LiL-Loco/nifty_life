import { cva, type VariantProps } from 'class-variance-authority';

import { cn } from '@/lib/utils';

/**
 * A raised panel.
 *
 * The site's one container. `surface` against `ground` is the only depth cue in
 * the portal — there are no shadows — so this component is the whole of it, and
 * a page that nests cards inside cards is nesting the same plane twice.
 *
 * `flush` exists for exactly one case: the admin tables, where a card's padding
 * would put a border-to-border gap between the table and the panel edge, and the
 * row separators would stop lining up with anything.
 */
const cardVariants = cva('rounded-lg border border-line bg-surface', {
  variants: {
    padding: {
      default: 'mb-4 p-5',
      flush: 'mb-4 overflow-hidden',
      none: '',
    },
    accent: {
      false: '',
      true: 'border-accent',
    },
  },
  defaultVariants: { padding: 'default', accent: false },
});

export function Card({
  className,
  padding,
  accent,
  ...props
}: React.HTMLAttributes<HTMLDivElement> & VariantProps<typeof cardVariants>) {
  return (
    <div className={cn(cardVariants({ padding, accent }), className)} {...props} />
  );
}