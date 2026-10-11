/**
 * The barrel.
 *
 * Pages import from `@/components/ui` rather than from six files. This is the one
 * place the component set is named in full, so adding a primitive is a one-line
 * change here and an unchanged import at every call site.
 */
export { Button, buttonLinkClass } from './button';
export { Card } from './card';
export { StatusPill } from './badge';
export { Notice } from './notice';
export { Field, Label } from './label';
export { AnswerBody, AnswerNumber, AnswerPair, Answers, Td, Th } from './table';