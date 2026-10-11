/**
 * The barrel.
 *
 * Pages import from `@/components/ui` rather than from nine files. This is the
 * one place the component set is named in full, so adding a primitive is a
 * one-line change here and an unchanged import at every call site.
 */
export { Button, buttonVariants } from './button';
export {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from './card';
export { Badge, badgeVariants } from './badge';
export { Alert, AlertDescription, AlertTitle } from './alert';
export { Input } from './input';
export { Textarea } from './textarea';
export { Label } from './label';
export {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableFooter,
  TableHead,
  TableHeader,
  TableRow,
} from './table';
export {
  Select,
  SelectContent,
  SelectGroup,
  SelectItem,
  SelectLabel,
  SelectScrollDownButton,
  SelectScrollUpButton,
  SelectSeparator,
  SelectTrigger,
  SelectValue,
} from './select';
