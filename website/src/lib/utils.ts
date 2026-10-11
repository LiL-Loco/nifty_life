import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

/**
 * The one class-name helper.
 *
 * `clsx` flattens conditionals; `tailwind-merge` resolves conflicts in favour of
 * the LAST utility. That second half is why this exists rather than plain
 * `clsx`: a component with `className="px-3"` inside and `className="px-6"`
 * passed in must end up `px-6`, and without `tailwind-merge` both classes are
 * emitted and which one wins depends on stylesheet order rather than on intent.
 *
 * Every `cn(...)` call in this repo is a component accepting a `className`, so
 * this is not an optimisation — it is the mechanism by which a caller can style a
 * component at all.
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}