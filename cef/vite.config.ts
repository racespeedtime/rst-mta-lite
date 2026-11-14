import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 构建产物直接写进 MTA 资源目录（ui/ 已被 .gitignore 忽略）。
const resourceUiDir = fileURLToPath(
  new URL('../server/mods/deathmatch/resources/[rst]/rst_ui/ui', import.meta.url),
)

export default defineConfig({
  base: './',
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  build: {
    outDir: resourceUiDir,
    emptyOutDir: true,
    target: 'chrome120',
    cssCodeSplit: false,
    // meta.xml 里要写死文件名，所以产物名固定、不哈希
    rollupOptions: {
      output: {
        entryFileNames: 'assets/app.js',
        chunkFileNames: 'assets/[name].js',
        assetFileNames: 'assets/[name][extname]',
      },
    },
  },
  server: {
    host: '127.0.0.1',
    port: 5173,
    open: false,
  },
})
