import { cva, type VariantProps } from 'class-variance-authority';

import { cn } from '@/lib/utils';

/**
 * The button.
 *
 * shadcn's shape, this project's palette. `cva` is what makes the variants
 * type-safe without a single class name being written at a call site: `variant`
 * and `size` are compile-time checked, so a typo is a build error rather than a
 * button that silently renders unstyled.
 *
 * The `secondary` variant is the important one. Almost every button on this site
 * is secondary — "anmelden", "abmelden", "löschen", "weitere ansehen" — and the
 * filled style is reserved for the one thing a screen is asking you to do. That
 * ratio is the difference between a form and a form with nine equally loud
 * buttons on it.
 *
 * The shared classes are INLINED rather than held in a `base` constant. `cva`
 * infers its argument types from the literal, and a `string[]` passed in from a
 * variable widens the signature to `VariantProps<...> | undefined` inside its
 * own return type, which then makes every call site fail to type-check.
 */
const buttonVariants = cva(
  'inline-block cursor-pointer rounded-md border font-semibold transition-[filter] hover:brightness-110 disabled:pointer-events-none disabled:opacity-45 focus-visible:outline-2 focus-visible:outline-offset-1 focus-visible:outline-accent',
  {
    variants: {
      variant: {
        default: 'border-accent bg-accent text-[#08111c]',
        secondary: 'border-line bg-transparent text-text',
        link: 'border-none bg-transparent p-0 text-accent underline',
      },
      size: {
        default: 'px-[1.1rem] py-[0.6rem]',
        sm: 'px-2.5 py-1 text-[0.8125rem]',
      },
    },
    defaultVariants: {
      variant: 'default',
      size: 'default',
    },
  },
);

type ButtonOptions = NonNullable<VariantProps<typeof buttonVariants>>;

/**
 * The class string, for a caller rendering its own element.
 *
 * Most of this site's buttons are `<Link>`s — anything that navigates must be an
 * anchor, or it loses middle-click, "open in new tab", and the address bar.
 * Forcing those through a `<button>` would trade real behaviour for a tidier
 * component API, so `Button` is for actions and `buttonLinkClass` is for
 * navigation, and both produce the same string.
 */
export function buttonLinkClass(props: ButtonOptions & { className?: string } = {}) {
  const { className, ...options } = props;
  return cn(buttonVariants(options), 'no-underline', className);
}

export function Button({
  className,
  variant,
  size,
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & ButtonOptions) {
  return <button className={cn(buttonVariants({ variant, size }), className)} {...props} />;
}