import { execSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Icons from 'unplugin-icons/vite'

// 构建期注入：优先直接读 .git/HEAD，失败再回退到 git 命令
function gitShortHash(): string {
  try {
    const gitDir = fileURLToPath(new URL('../.git', import.meta.url))
    const head = readFileSync(`${gitDir}/HEAD`, 'utf8').trim()

    if (head.startsWith('ref: ')) {
      const ref = head.slice(5).trim()
      return readFileSync(`${gitDir}/${ref}`, 'utf8').trim().slice(0, 7)
    }
    return head.slice(0, 7)
  } catch {
    try {
      return execSync('git rev-parse --short HEAD', {
        cwd: fileURLToPath(new URL('..', import.meta.url)),
        stdio: ['ignore', 'pipe', 'ignore'],
      })
        .toString()
        .trim()
    } catch {
      return 'dev'
    }
  }
}

function buildDateParts(): { date: string; time: string } {
  const now = new Date()
  const pad = (value: number) => String(value).padStart(2, '0')

  return {
    date: `${now.getFullYear()}.${pad(now.getMonth() + 1)}.${pad(now.getDate())}`,
    time: now.toISOString(),
  }
}

const buildDate = buildDateParts()
const buildHash = gitShortHash()

// 构建产物直接写进 MTA 资源目录（ui/ 已被 .gitignore 忽略）。
const resourceUiDir = fileURLToPath(
  new URL('../server/mods/deathmatch/resources/[rst]/rst_ui/ui', import.meta.url),
)

export default defineConfig({
  base: './',
  plugins: [vue(), Icons({ compiler: 'vue3' })],
  define: {
    __RST_BUILD_DATE__: JSON.stringify(buildDate.date),
    __RST_BUILD_TIME__: JSON.stringify(buildDate.time),
    __RST_BUILD_HASH__: JSON.stringify(buildHash),
  },
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
