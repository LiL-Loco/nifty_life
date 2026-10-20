import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  base: './',
  plugins: [react(), tailwindcss()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    // CEF in FiveM is a Chromium build from ~2023.
    target: 'es2020',
    sourcemap: false,
    chunkSizeWarningLimit: 900,
  },
});
