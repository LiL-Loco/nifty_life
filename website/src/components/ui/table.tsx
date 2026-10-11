import { cn } from '@/lib/utils';

/**
 * A table cell.
 *
 * `head` is one boolean rather than a separate component because the only
 * difference between a header cell and a body cell on this site is weight,
 * colour and letter-spacing — and getting one of those three wrong is the kind of
 * thing that is invisible in review and obvious on the page.
 */
export function Th({
  className,
  ...props
}: React.ThHTMLAttributes<HTMLTableCellElement>) {
  return (
    <th
      className={cn(
        'px-[0.8rem] py-[0.6rem] text-left text-xs uppercase tracking-[0.06em] text-muted',
        className,
      )}
      {...props}
    />
  );
}

export function Td({
  className,
  ...props
}: React.TdHTMLAttributes<HTMLTableCellElement>) {
  return (
    <td
      className={cn(
        'border-t border-line px-[0.8rem] py-[0.6rem] align-top text-[0.9rem]',
        className,
      )}
      {...props}
    />
  );
}

/**
 * The answers list on the review screen.
 *
 * Twenty questions rendered as twenty cards stop reading as twenty ANSWERS — each
 * card looks like a section of the page instead of a prompt and a reply. What
 * makes a review workable is that a question and its answer cannot be separated by
 * scrolling: a fixed number, the question, the answer indented beneath it, a
 * hairline between pairs.
 *
 * The number is not decoration. Reviewing twenty answers means saying "question 7"
 * in a Discord conversation an hour later, and an ordinal is the only identifier
 * that survives a reworded rulebook.
 */
export function Answers({ className, ...props }: React.HTMLAttributes<HTMLOListElement>) {
  return (
    <ol
      className={cn(
        'm-0 list-none overflow-hidden rounded-lg border border-line p-0',
        className,
      )}
      {...props}
    />
  );
}

export function AnswerPair({ className, ...props }: React.LiHTMLAttributes<HTMLLIElement>) {
  return <li className={cn('border-t border-line px-[1.1rem] py-4', className)} {...props} />;
}

export function AnswerNumber({ className, ...props }: React.HTMLAttributes<HTMLSpanElement>) {
  return (
    <span
      className={cn(
        'inline-flex size-[1.4rem] flex-none items-center justify-center rounded-full',
        'border border-line text-[0.72rem] text-muted tabular-nums',
        className,
      )}
      {...props}
    />
  );
}

export function AnswerBody({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return (
    <div
      className={cn('mt-2 ml-[2.1rem] whitespace-pre-wrap border-l-2 border-l-accent pl-[0.9rem]', className)}
      {...props}
    />
  );
}