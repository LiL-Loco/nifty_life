import * as React from 'react';
import { createRoot } from 'react-dom/client';

import './loadscreen.css';
import { LoadScreen } from './LoadScreen';

const host = document.getElementById('root');
if (!host) throw new Error('nifty-loadscreen: #root missing from index.html');

createRoot(host).render(
  <React.StrictMode>
    <LoadScreen />
  </React.StrictMode>,
);
