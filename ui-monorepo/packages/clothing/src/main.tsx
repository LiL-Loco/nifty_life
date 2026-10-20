import * as React from 'react';
import { createRoot } from 'react-dom/client';

// The shared stylesheet carries the website's design tokens AND the three
// CEF-specific rules every panel needs (`background: transparent`,
// `overflow: hidden`, `.hidden`). Without this import the build succeeds,
// ships no CSS at all, and the panel renders unstyled — a green build that
// proves nothing. Same trap as the Tailwind entry in LEARNINGS.md.
import '@nifty/ui/styles.css';
import { ClothingPanel } from './ClothingPanel';

const host = document.getElementById('root');
if (!host) throw new Error('nifty-clothing: #root missing from index.html');

createRoot(host).render(
  <React.StrictMode>
    <ClothingPanel />
  </React.StrictMode>,
);