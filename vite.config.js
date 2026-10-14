import { defineConfig } from 'vite';
import tailwindcss from '@tailwindcss/vite';

// base = nome do repositório no GitHub Pages (https://jeriterrenos.github.io/green/)
export default defineConfig({
  base: '/green/',
  plugins: [tailwindcss()],
  server: { open: true },
  build: {
    // MapLibre (~1 MB) fica num arquivo separado, que o navegador guarda em cache entre versões do app
    rollupOptions: { output: { manualChunks: { maplibre: ['maplibre-gl'] } } },
    chunkSizeWarningLimit: 1100,
  },
});
