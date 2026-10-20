/**
 * @nifty/ui — the shared NUI surface.
 *
 * Two rules every consumer inherits:
 *
 * 1. Design tokens come from the website (see styles.css). A panel that
 *    invents its own colours has broken the brand, not extended it.
 * 2. Every panel names its OWN Lua actions through @nifty/bridge, so two
 *    resources cannot claim the same `action` string without the build
 *    failing. That collision is not hypothetical — it is what covered the
 *    character creator for an evening.
 */
export { cn } from './lib/utils';

export { Button, buttonVariants, type ButtonProps } from './components/button';
export {
  Card,
  CardHeader,
  CardTitle,
  CardDescription,
  CardContent,
  CardFooter,
} from './components/card';
export { Slider } from './components/slider';
export { ScrollArea, ScrollBar } from './components/scroll-area';
export {
  Separator,
  Tabs,
  TabsList,
  TabsTrigger,
  TabsContent,
  ToggleGroup,
  ToggleGroupItem,
} from './components/primitives';
export {
  Grid2D,
  Grid1DH,
  Grid1DV,
  DragDot,
  type Vec2,
  type DragSurfaceProps,
} from './components/drag-grid';

export {
  createBridge,
  callLua,
  type ActionMap,
  type Bridge,
  type Result,
  type NuiMessage,
} from '@nifty/bridge';