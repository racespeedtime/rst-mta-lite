#!/usr/bin/env node
/**
 * mtavault.com DM 地图元数据抓取脚本（手动运行，不随服务器启动）
 *
 * 只抓元数据，不下载地图资源本身。字段按需精简：名称 / 作者 / 上传日期 /
 * 热度（下载量）/ 封面 / 难度 / 文件大小 / 标签 / 源站链接。
 *
 * 用法：
 *   node tools/mtavault/fetch-dm-maps.mjs
 *   node tools/mtavault/fetch-dm-maps.mjs --out tools/mtavault/output/dm-maps.json
 *   node tools/mtavault/fetch-dm-maps.mjs --cover-dir tools/mtavault/output/covers
 *   node tools/mtavault/fetch-dm-maps.mjs --max-pages 2 --page-size 20   # 调试
 *
 * 说明：
 * - 走 https://api.mtavault.com/maps，不解析网页 HTML
 * - 分页拉全量后按 tags / fileName 里的 DM 过滤
 * - 封面优先用 videoURL 对应的 YouTube 缩略图；--cover-dir 会把封面下载到本地
 * - 默认按下载量降序（sort=downloads&direction=-1）
 */

import { mkdir, writeFile } from 'node:fs/promises'
import { spawn } from 'node:child_process'
import { dirname, join, relative, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const REPO_ROOT = fileURLToPath(new URL('../..', import.meta.url))

function parseArgs(argv) {
  const options = {
    apiBase: 'https://api.mtavault.com',
    siteBase: 'https://mtavault.com',
    out: join(REPO_ROOT, 'tools/mtavault/output/dm-maps.json'),
    coverDir: '',
    pageSize: 100,
    maxPages: 0,
    delay: 150,
    coverLimit: 0,
    tag: 'DM',
    retries: 3,
    timeout: 20000,
    proxy: process.env.HTTPS_PROXY || process.env.https_proxy || '',
  }

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    const next = () => {
      i += 1
      if (i >= argv.length) throw new Error(`${arg} 缺少参数`)
      return argv[i]
    }

    switch (arg) {
      case '--help':
      case '-h':
        options.help = true
        break
      case '--api-base':
        options.apiBase = next().replace(/\/+$/, '')
        break
      case '--site-base':
        options.siteBase = next().replace(/\/+$/, '')
        break
      case '--out':
        options.out = resolve(process.cwd(), next())
        break
      case '--cover-dir':
        options.coverDir = resolve(process.cwd(), next())
        break
      case '--page-size':
        options.pageSize = Math.max(1, Number(next()) || 100)
        break
      case '--max-pages':
        options.maxPages = Math.max(0, Number(next()) || 0)
        break
      case '--delay':
        options.delay = Math.max(0, Number(next()) || 0)
        break
      case '--cover-limit':
        options.coverLimit = Math.max(0, Number(next()) || 0)
        break
      case '--tag':
        options.tag = next()
        break
      case '--retries':
        options.retries = Math.max(1, Number(next()) || 3)
        break
      case '--timeout':
        options.timeout = Math.max(1000, Number(next()) || 20000)
        break
      case '--proxy':
        options.proxy = next()
        break
      default:
        throw new Error(`未知参数：${arg}`)
    }
  }

  return options
}

const sleep = (ms) => new Promise((resolvePromise) => setTimeout(resolvePromise, ms))

async function request(url, options, as = 'json') {
  let lastError
  for (let attempt = 1; attempt <= options.retries; attempt += 1) {
    try {
      const response = await fetch(url, {
        headers: {
          accept: as === 'json' ? 'application/json' : 'image/*,*/*',
          'user-agent': 'rst-mta-lite-map-metadata/1.0',
        },
        signal: AbortSignal.timeout(options.timeout),
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status} ${response.statusText}`)
      }

      if (as === 'buffer') {
        return Buffer.from(await response.arrayBuffer())
      }

      const payload = await response.json()
      if (payload && typeof payload.statusCode === 'number' && payload.statusCode >= 400) {
        throw new Error(`API statusCode ${payload.statusCode}`)
      }
      return payload
    } catch (error) {
      lastError = error
      if (attempt < options.retries) {
        await sleep(400 * attempt)
      }
    }
  }
  throw lastError
}

function listUrl(options, page) {
  const url = new URL(`${options.apiBase}/maps`)
  url.searchParams.set('page', String(page))
  url.searchParams.set('size', String(options.pageSize))
  url.searchParams.set('sort', 'downloads')
  url.searchParams.set('direction', '-1')
  return url.toString()
}

function tagNames(map) {
  if (!Array.isArray(map.tags)) return []
  return map.tags
    .map((tag) => (typeof tag === 'string' ? tag : tag?.name))
    .filter((tag) => typeof tag === 'string' && tag.trim())
}

function isDmMap(map, tag) {
  const wanted = tag.toLowerCase()
  if (tagNames(map).some((name) => name.toLowerCase() === wanted)) return true

  const bracket = new RegExp(`\\[${tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\]`, 'i')
  return bracket.test(map.fileName || '') || bracket.test(map.name || '')
}

function youtubeId(value) {
  if (typeof value !== 'string') return ''
  const id = value.trim()
  if (!id) return ''
  if (/^[A-Za-z0-9_-]{6,}$/.test(id)) return id

  const match = id.match(/(?:youtu\.be\/|v=|\/embed\/)([A-Za-z0-9_-]{6,})/)
  return match ? match[1] : ''
}

function coverUrlFor(map) {
  const id = youtubeId(map.videoURL)
  return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : ''
}

function uploadedDate(value) {
  if (!value) return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date.toISOString().slice(0, 10)
}

function normalize(map, options, coverLocal) {
  const seo = map.seoFriendlyURL || map.id
  return {
    id: map.id,
    name: map.name || map.meta?.name || map.fileName || '未命名地图',
    authors: Array.isArray(map.authors)
      ? [...new Set(map.authors.map((author) => author?.name).filter(Boolean))]
      : [],
    uploadedAt: uploadedDate(map.createdAt),
    // 热度先取源站下载量；服务器内游玩次数会在运行时再加权
    popularity: Number(map.downloads) || 0,
    difficulty: map.difficulty || null,
    fileSize: Number(map.fileSize) || 0,
    tags: tagNames(map).slice(0, 8),
    fileName: map.fileName || '',
    sourceUrl: `${options.siteBase}/map/${seo}`,
    coverUrl: coverUrlFor(map) || null,
    coverLocal: coverLocal || null,
  }
}

async function fetchAllMaps(options) {
  const all = []
  let page = 1
  let total = 0

  while (true) {
    const payload = await request(listUrl(options, page), options)
    const data = payload?.data ?? payload
    const maps = Array.isArray(data?.maps) ? data.maps : []
    total = Number(data?.totalItems) || total

    console.error(
      `[mtavault] page ${page}: +${maps.length}, total ${all.length}/${total || '?'}`,
    )

    all.push(...maps)

    const reachedTotal = total > 0 && all.length >= total
    const reachedMax = options.maxPages > 0 && page >= options.maxPages
    if (maps.length === 0 || reachedTotal || reachedMax) break

    page += 1
    if (options.delay > 0) await sleep(options.delay)
  }

  return { maps: all, total }
}

async function downloadCovers(maps, options) {
  if (!options.coverDir) return

  await mkdir(options.coverDir, { recursive: true })

  let downloaded = 0
  let attempted = 0

  for (const map of maps) {
    if (!map.coverUrl) continue
    if (options.coverLimit > 0 && attempted >= options.coverLimit) break
    attempted += 1

    const file = join(options.coverDir, `${map.id}.jpg`)
    try {
      if (!options.proxy) {
        try {
          const buffer = await request(map.coverUrl, options, 'buffer')
          await writeFile(file, buffer)
          map.coverLocal = relative(dirname(options.out), file).replaceAll('\\', '/')
          downloaded += 1
          if (options.delay > 0) await sleep(options.delay)
          continue
        } catch {
          // 某些网络下 Node fetch 取不到 YouTube 缩略图，回退到 curl
        }
      }

      await new Promise((resolvePromise, reject) => {
        const args = [
          '--location',
          '--fail',
          '--silent',
          '--show-error',
          '-A',
          'rst-mta-lite-map-metadata/1.0',
        ]
        if (options.proxy) args.push('--proxy', options.proxy)
        args.push('-o', file, map.coverUrl)

        const child = spawn('curl', args, { stdio: 'ignore' })
        child.on('error', reject)
        child.on('exit', (code) => {
          if (code === 0) resolvePromise()
          else reject(new Error(`curl exit ${code}`))
        })
      })

      map.coverLocal = relative(dirname(options.out), file).replaceAll('\\', '/')
      downloaded += 1
    } catch (error) {
      console.error(`[mtavault] cover failed for ${map.id}: ${error.message}`)
    }

    if (options.delay > 0) await sleep(options.delay)
  }

  console.error(`[mtavault] covers: ${downloaded}/${attempted}`)
}

async function main() {
  const options = parseArgs(process.argv.slice(2))

  if (options.help) {
    console.log(
      [
        'mtavault DM 地图元数据抓取',
        '',
        '  --out <file>        输出 JSON，默认 tools/mtavault/output/dm-maps.json',
        '  --cover-dir <dir>   同时下载封面到目录（可选）',
        '  --cover-limit <n>   最多下载多少张封面，0 = 不限',
        '  --page-size <n>     每页数量，默认 100',
        '  --max-pages <n>     最多抓多少页，0 = 全部（调试用）',
        '  --delay <ms>        请求间隔，默认 150ms',
        '  --tag <name>        过滤标签，默认 DM',
        '  --api-base <url>    默认 https://api.mtavault.com',
        '  --retries <n>       请求重试次数，默认 3',
        '  --timeout <ms>      单次请求超时，默认 20000',
        '  --proxy <url>       封面下载代理，如 http://127.0.0.1:7890；默认读 HTTPS_PROXY',
      ].join('\n'),
    )
    return
  }

  console.error(`[mtavault] API: ${options.apiBase}`)
  console.error(`[mtavault] filter tag: ${options.tag}`)

  const { maps: rawMaps, total } = await fetchAllMaps(options)

  const seen = new Set()
  const normalized = []
  for (const raw of rawMaps) {
    if (!raw || !raw.id || seen.has(raw.id)) continue
    if (!isDmMap(raw, options.tag)) continue
    seen.add(raw.id)
    normalized.push(normalize(raw, options, null))
  }

  normalized.sort((a, b) => b.popularity - a.popularity)

  await downloadCovers(normalized, options)

  const output = {
    source: 'mtavault',
    apiBase: options.apiBase,
    fetchedAt: new Date().toISOString(),
    filter: { tag: options.tag },
    sourceTotal: total,
    count: normalized.length,
    maps: normalized,
  }

  await mkdir(dirname(options.out), { recursive: true })
  await writeFile(options.out, `${JSON.stringify(output, null, 2)}\n`, 'utf8')

  console.log(`[mtavault] wrote ${normalized.length} DM maps to ${options.out}`)
}

main().catch((error) => {
  console.error(`[mtavault] failed: ${error.stack || error.message}`)
  process.exitCode = 1
})
