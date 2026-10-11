import { cn } from '@/lib/utils';

/**
 * A label bound to an input.
 *
 * The `htmlFor` is not a convenience — it is what makes the label clickable and
 * what a screen reader announces when focus lands on the field. The pairing is
 * enforced by the required `htmlFor` prop rather than by a `useId()`: the caller
 * already has the `id` it passed to the input, and generating a second one risks
 * a label that points at nothing.
 */
export function Label({
  className,
  ...props
}: React.LabelHTMLAttributes<HTMLLabelElement>) {
  return (
    <label
      className={cn('mb-1 block text-sm text-muted', className)}
      {...props}
    />
  );
}

/**
 * A label above a form control.
 *
 * The vertical rhythm of a form comes from here, not from margins on individual
 * inputs: twenty fields in the application wizard each get the same gap below
 * them without anyone having to remember it.
 */
export function Field({
  className,
  ...props
}: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn('mb-[1.1rem]', className)} {...props} />;
}