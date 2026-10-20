import * as React from 'react';
import { Button, Card, ScrollArea } from '@nifty/ui';
import { send, type WorldState } from '../contract';
import { JobsPanel } from './JobsPanel';
import { ShopPanel } from './ShopPanel';

/**
 * The modal panel shell.
 *
 * The builder map is keyed by the panel names this surface can actually draw.
 * `render.panel` is a plain string on the wire (cl_world.lua forwards whatever
 * `RegisterCommand('niftypanel', …)` matched), so `'properties'` and
 * `'vehicles'` are legal Lua states with no builder here — they render nothing,
 * exactly as the old ui/app.js did. Adding a builder is a one-line change to
 * this map; inventing one during a port would be writing a feature nobody
 * asked for and inventing its German copy along with it.
 */
const PANELS: Record<
  string,
  { title: string; render: (state: WorldState) => React.ReactNode }
> = {
  shop: {
    title: 'Shop',
    render: (state) => (
      <ShopPanel
        shop={state.shop}
        inventory={state.inventory}
        cash={state.money.cash}
      />
    ),
  },
  jobs: {
    title: 'Arbeit',
    render: (state) => (
      <JobsPanel jobs={state.jobs} catalogue={state.jobCatalogue} />
    ),
  },
};

export function PanelShell({ state }: { state: WorldState }) {
  const entry = state.panel ? PANELS[state.panel] : undefined;
  if (!entry) return null;

  return (
    <div className="fixed inset-0 z-[50] flex items-center justify-center bg-[rgba(0,0,0,0.55)]">
      <Card className="flex max-h-[76vh] w-[min(620px,84vw)] flex-col overflow-hidden">
        <header className="flex shrink-0 items-center justify-between border-b border-[var(--color-border)] px-4 py-3">
          <h2 className="m-0 text-xs font-semibold uppercase tracking-[0.12em] text-[rgba(242,242,240,0.82)]">
            {entry.title}
          </h2>
          <Button
            size="sm"
            variant="ghost"
            onClick={() => {
              void send('closePanel', {});
            }}
          >
            Schließen
          </Button>
        </header>

        <ScrollArea className="min-h-0 flex-1">
          <div className="px-4 pb-4 pt-3.5">{entry.render(state)}</div>
        </ScrollArea>
      </Card>
    </div>
  );
}