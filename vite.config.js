import { resolve } from 'node:path';
import { defineConfig } from 'vite';

// two pages: the playable prototype (index.html) and the original still look test (look.html)
export default defineConfig({
  base: './',
  build: {
    chunkSizeWarningLimit: 900, // three.js is one big chunk
    rollupOptions: {
      input: { main: resolve(import.meta.dirname, 'index.html'), look: resolve(import.meta.dirname, 'look.html') },
    },
  },
});
