import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import { resolve } from 'node:path';

/**
 * `base: './'` is not optional.
 *
 * FiveM serves the built panel from `https://cfx-nui-nifty-chat/ui/dist/`.
 * With the default `base: '/'` Vite emits `/assets/index-*.js`, and CEF resolves
 * that against the ORIGIN — which is `https://cfx-nui-nifty-chat` without the
 * `/ui/dist/` path, so every asset 404s and the panel is a blank frame.
 *
 * The same trap is documented in resources/myphone/ui/vite.config.ts, which is
 * a downloaded third-party resource — copied here as a reference, not as
 * infrastructure we own.
 */
export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      // Order matters: the bare `@nifty/ui` must come AFTER the subpath, or
      // it swallows `@nifty/ui/styles.css` and the build fails looking for
      // `<dir>/index.ts/styles.css`.
      '@nifty/ui/styles.css': resolve(__dirname, '../ui/src/styles.css'),
      '@nifty/ui': resolve(__dirname, '../ui/src/index.ts'),
      '@nifty/bridge': resolve(__dirname, '../bridge/src/index.ts'),
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // CEF in FiveM is a Chromium build from ~2023. Targeting es2020 keeps
    // optional chaining, nullish coalescing and class fields off the output.
    target: 'es2020',
    sourcemap: false,
    chunkSizeWarningLimit: 900,
  },
});