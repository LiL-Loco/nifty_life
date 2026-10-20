import * as React from 'react';
import { Slot } from '@radix-ui/react-slot';
import { cva, type VariantProps } from 'class-variance-authority';
import { cn } from '../lib/utils';

const buttonVariants = cva(
  'inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-full text-sm font-extrabold uppercase tracking-[0.06em] transition-transform duration-100 disabled:pointer-events-none disabled:opacity-40',
  {
    variants: {
      variant: {
        default: 'bg-[var(--color-primary)] text-[var(--color-primary-foreground)] hover:brightness-110 active:translate-y-0',
        ghost: 'bg-[var(--color-secondary)] text-[var(--color-foreground)] hover:bg-[var(--color-accent)]',
        outline:
          'border-3 border-[var(--color-background)] bg-transparent text-[var(--color-foreground)] hover:bg-[var(--color-secondary)]',
        destructive: 'bg-destructive text-[var(--color-foreground)] hover:brightness-110',
      },
      size: {
        default: 'h-9 px-4 py-2',
        sm: 'h-8 px-3 text-xs',
        lg: 'h-11 px-6 text-base',
        icon: 'h-9 w-9 p-0',
      },
      active: {
        true: 'translate-y-[-1px]',
        false: '',
      },
    },
    defaultVariants: { variant: 'default', size: 'default', active: false },
  },
);

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  asChild?: boolean;
}

export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, active, asChild = false, type, ...props }, ref) => {
    const Comp = asChild ? Slot : 'button';
    return (
      <Comp
        ref={ref}
        // Buttons inside the old panels defaulted to type="submit"; a stray
        // <form> ancestor turned every click into a page navigation. CEF loads
        // these documents like a browser does, so this defaults to button.
        type={asChild ? undefined : (type ?? 'button')}
        className={cn(buttonVariants({ variant, size, active }), className)}
        {...props}
      />
    );
  },
);
Button.displayName = 'Button';

export { buttonVariants };