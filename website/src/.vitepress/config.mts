import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'
import { existsSync, readFileSync, readdirSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve, sep } from 'node:path'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const docsVersion = process.env.PERFCHECKER_DOCS_VERSION ?? '1.0.0'
const docsURL = new URL(process.env.PERFCHECKER_DOCS_URL ?? 'https://perfchecker.mirageinteractive.fr/')
const localPreview = process.env.PERFCHECKER_DOCS_LOCAL_PREVIEW === 'true'
const previewURL = localPreview && docsURL.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(docsURL.hostname)
if ((!previewURL && docsURL.protocol !== 'https:') || docsURL.username || docsURL.password || docsURL.search || docsURL.hash)
  throw new Error('Documentation deployment URL must be plain HTTPS')
const sftp = (process.env.PERFCHECKER_DOCS_HOSTING ??
  (docsURL.origin === 'https://perfchecker.mirageinteractive.fr' ? 'sftp' : 'github')) === 'sftp'
const docsChannel = process.env.PERFCHECKER_DOCS_CHANNEL ?? 'stable'

// Use this config's public tree: Documenter has already copied the source tree
// when VitePress loads its generated config. Fetched assets must enter that copy.
const mediaRoot = resolve(fileURLToPath(new URL('../public/', import.meta.url)))
// Reserve the real image/poster geometry before lazy images finish loading.
// Without it, a route's fragment can move below the viewport after navigation.
function imageDimensions(bytes: Buffer): { width: number; height: number } {
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')))
    return { width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) }
  if (bytes.length >= 2 && bytes.readUInt16BE(0) === 0xffd8) {
    for (let at = 2; at + 9 <= bytes.length;) {
      if (bytes[at] !== 0xff) break
      const marker = bytes[at + 1]
      if (marker === 0xff) { at++; continue }
      if (marker === 0xda || marker === 0xd9) break
      const length = bytes.readUInt16BE(at + 2)
      if (length < 2 || at + length + 2 > bytes.length) break
      if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker))
        return { width: bytes.readUInt16BE(at + 7), height: bytes.readUInt16BE(at + 5) }
      at += length + 2
    }
  }
  const svg = bytes.toString('utf8').match(/<svg\b[^>]*>/i)?.[0]
  if (svg) {
    const attribute = (name: string) => svg.match(new RegExp(`\\b${name}\\s*=\\s*(["'])(.*?)\\1`, 'i'))?.[2]
    const viewBox = attribute('viewBox')?.trim().split(/[\s,]+/).map(Number)
    if (viewBox?.length === 4 && viewBox.every(Number.isFinite) && viewBox[2] > 0 && viewBox[3] > 0)
      return { width: viewBox[2], height: viewBox[3] }
    const pixels = (value: string | undefined) => value?.match(/^\s*(\d+(?:\.\d+)?)\s*(?:px)?\s*$/i)?.[1]
    const width = Number(pixels(attribute('width')))
    const height = Number(pixels(attribute('height')))
    if (width > 0 && height > 0) return { width, height }
  }
  throw new Error('Local image has no supported PNG/JPEG/SVG dimensions')
}
const imageSizes: Record<string, { width: number; height: number }> = {}
function collectImageSizes(directory: string, prefix = '') {
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const name = prefix + entry.name
    if (entry.isDirectory()) collectImageSizes(resolve(directory, entry.name), name + '/')
    else if (/\.(?:png|jpe?g|svg)$/i.test(entry.name)) {
      const size = imageDimensions(readFileSync(resolve(directory, entry.name)))
      if (size.width <= 0 || size.height <= 0) throw new Error(`Invalid image dimensions: ${name}`)
      imageSizes['/' + name] = size
    }
  }
}
const media = JSON.parse(readFileSync(resolve(process.cwd(), 'media.json'), 'utf8'))
for (const item of Object.values(media) as any[]) {
  const file = resolve(mediaRoot, item.file)
  if (!file.startsWith(mediaRoot + sep)) throw new Error('Recording escapes the public directory')
  if (item.youtube_id && !/^[A-Za-z0-9_-]{11}$/.test(item.youtube_id)) throw new Error('Invalid YouTube video ID')
  if (item.download_url && !item.download_url.startsWith('https://')) throw new Error('Recording downloads require HTTPS')
  if (item.embed_local) {
    if (!Number.isSafeInteger(item.bytes) || item.bytes <= 0 || !/^[a-f0-9]{64}$/.test(item.sha256))
      throw new Error(`Embedded recording requires exact bytes and SHA256: ${item.file}`)
    const download = new URL(item.download_url)
    if (download.protocol !== 'https:' || download.username || download.password || download.hash)
      throw new Error('Embedded recording download must be plain HTTPS')
    if (!existsSync(file)) {
      const deadline = AbortSignal.timeout(120_000)
      let bytes: Buffer
      try {
        const response = await fetch(download, { signal: deadline })
        if (!response.ok) throw new Error(`HTTP ${response.status}`)
        bytes = Buffer.from(await response.arrayBuffer())
      } catch (error) {
        const reason = deadline.aborted ? 'timed out after 120 seconds' :
          error instanceof Error ? error.message : String(error)
        throw new Error(`Recording download failed for ${item.file}: ${reason}`)
      }
      if (bytes.length !== item.bytes || createHash('sha256').update(bytes).digest('hex') !== item.sha256)
        throw new Error(`Downloaded recording does not match media.json: ${item.file}`)
      mkdirSync(dirname(file), { recursive: true })
      writeFileSync(file, bytes, { flag: 'wx' })
    }
  }
  item.local_available = existsSync(file)
  if (item.local_available) {
    const bytes = readFileSync(file)
    if (bytes.length !== item.bytes || createHash('sha256').update(bytes).digest('hex') !== item.sha256)
      throw new Error(`Recording does not match media.json: ${item.file}`)
  }
}
collectImageSizes(mediaRoot)

const config = defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  lastUpdated: true,
  // Plain static hosting through SFTP needs no rewrite rules for .html links.
  cleanUrls: !sftp,
  vite: { define: {
    __PERFCHECKER_MEDIA__: JSON.stringify(media),
    __PERFCHECKER_IMAGES__: JSON.stringify(imageSizes),
    __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'),
    __PERFCHECKER_DOCS_VERSION__: JSON.stringify(docsChannel === 'dev' ? 'dev' : `v${docsVersion}`),
  } },
  ignoreDeadLinks: false,
  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin)
      md.use(footnote)
    },
    theme: { light: 'github-light', dark: 'github-dark' },
  },
  themeConfig: {
    logo: '/assets/perfchecker-mark.png',
    sidebarDrawer: 'REPLACE_ME_DOCUMENTER_VITEPRESS_SIDEBAR_DRAWER',
    outline: { level: [2, 3], label: 'On this page' },
    search: {
      provider: 'local',
      options: { detailedView: true },
    },
    nav: [
      {
        "text": "Manual",
        "link": "/guide/overview"
      },
      {
        "text": "Examples",
        "items": [
          {
            "text": "Bibliography",
            "link": "/tutorials/bibliography"
          },
          {
            "text": "DataStructures",
            "link": "/real-packages/datastructures"
          },
          {
            "text": "Oxygen",
            "link": "/real-packages/oxygen"
          }
        ]
      },
      {
        "text": "Interfaces",
        "items": [
          {
            "text": "VS Code",
            "link": "/interfaces/vscode"
          },
          {
            "text": "Web (Oxygen)",
            "link": "/interfaces/web-studio"
          },
          {
            "text": "Pluto",
            "link": "/interfaces/pluto"
          },
          {
            "text": "REPL",
            "link": "/interfaces/repl"
          },
          {
            "text": "Makie",
            "link": "/interfaces/visualization"
          },
          {
            "text": "Documenter",
            "link": "/interfaces/documentation"
          },
          {
            "text": "Tachikoma",
            "link": "/interfaces/tachikoma"
          }
        ]
      },
      {
        "text": "Tools",
        "items": [
          {
            "text": "Timing",
            "items": [
              {
                "text": "BenchmarkTools",
                "link": "/tools/benchmarktools"
              },
              {
                "text": "Chairmarks",
                "link": "/tools/chairmarks"
              },
              {
                "text": "TestItemRunner",
                "link": "/tools/testitemrunner"
              }
            ]
          },
          {
            "text": "Profiles",
            "items": [
              {
                "text": "CPU profile",
                "link": "/tools/cpu-profile"
              },
              {
                "text": "Wall profile",
                "link": "/tools/wall-profile"
              },
              {
                "text": "Allocation profile",
                "link": "/tools/allocation-profile"
              },
              {
                "text": "Line allocations",
                "link": "/tools/line-allocations"
              },
              {
                "text": "PProf",
                "link": "/tools/pprof"
              },
              {
                "text": "FlameGraphs",
                "link": "/tools/flamegraphs"
              }
            ]
          },
          {
            "text": "Diagnostics",
            "items": [
              {
                "text": "JET",
                "link": "/tools/jet"
              },
              {
                "text": "AllocCheck",
                "link": "/tools/alloccheck"
              },
              {
                "text": "SnoopCompile",
                "link": "/tools/snoopcompile"
              },
              {
                "text": "Latency",
                "link": "/tools/latency"
              },
              {
                "text": "GC",
                "link": "/tools/gc"
              },
              {
                "text": "Memory",
                "link": "/tools/memory"
              },
              {
                "text": "Locks",
                "link": "/tools/locks"
              },
              {
                "text": "Aqua",
                "link": "/tools/aqua"
              },
              {
                "text": "Heap snapshot",
                "link": "/tools/heap-snapshot"
              }
            ]
          },
          {
            "text": "Workloads and results",
            "items": [
              {
                "text": "DrWatson",
                "link": "/tools/drwatson"
              },
              {
                "text": "PropCheck",
                "link": "/tools/propcheck"
              },
              {
                "text": "Supposition",
                "link": "/tools/supposition"
              },
              {
                "text": "Scenarios",
                "link": "/tools/scenarios"
              },
              {
                "text": "Saved results",
                "link": "/tools/results"
              },
              {
                "text": "Command line",
                "link": "/tools/cli"
              },
              {
                "text": "Network",
                "link": "/tools/network"
              },
              {
                "text": "Machine profiles",
                "link": "/tools/machine"
              },
              {
                "text": "Preferences",
                "link": "/tools/preferences"
              },
              {
                "text": "PkgEval",
                "link": "/tools/pkgeval"
              },
              {
                "text": "Julia runtimes",
                "link": "/tools/julia-runtimes"
              }
            ]
          },
          {
            "text": "Native tools",
            "items": [
              {
                "text": "Memcheck",
                "link": "/tools/memcheck"
              },
              {
                "text": "Callgrind",
                "link": "/tools/callgrind"
              },
              {
                "text": "Massif",
                "link": "/tools/massif"
              },
              {
                "text": "Cachegrind",
                "link": "/tools/cachegrind"
              },
              {
                "text": "heaptrack",
                "link": "/tools/heaptrack"
              },
              {
                "text": "Linux perf",
                "link": "/tools/linux-perf"
              },
              {
                "text": "VTune",
                "link": "/tools/vtune"
              },
              {
                "text": "LinuxPerf companion",
                "link": "/tools/linuxperf"
              },
              {
                "text": "LIKWID",
                "link": "/tools/likwid"
              }
            ]
          }
        ]
      },
      {
        "text": "Agentic workflows",
        "items": [
          {
            "text": "Connect an MCP tool",
            "link": "/agentic/mcp"
          },
          {
            "text": "Advice → implementation",
            "link": "/agentic/advice"
          },
          {
            "text": "Providers",
            "link": "/agentic/providers"
          }
        ]
      },
      {
        "text": "API",
        "items": [
          {
            "text": "Public API",
            "link": "/reference/public-api"
          },
          {
            "text": "Full API",
            "link": "/reference/api"
          },
          {
            "text": "Companion APIs",
            "link": "/reference/optional-api"
          }
        ]
      },
      {
        "component": "VersionPicker"
      }
    ],
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    editLink: {
      pattern: 'https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/edit/main/website/src/:path',
      text: 'Edit this page',
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/Mirage-Interactive-Fr/PerfChecker.jl' },
    ],
    footer: {
      message: 'Open source · <a href="https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues">Report an issue</a> · Contributions welcome',
      copyright: `© ${new Date().getUTCFullYear()} PerfChecker contributors`,
    },
  },
})

// The qualification job builds the actual deployment path without requiring
// a publishing credential in the build/test jobs.
if (process.env.PERFCHECKER_DOCS_BASE) {
  const base = process.env.PERFCHECKER_DOCS_BASE
  if (!/^\/(?:[A-Za-z0-9._-]+\/)*$/.test(base)) throw new Error('Invalid documentation base')
  config.base = base
}

// Root exports include their own metadata; Documenter supplies it for mirrors.
if (sftp) {
  config.head = [
    ['script', { src: '/versions.js' }],
    ['script', { src: `${config.base}siteinfo.js` }],
  ]
} else {
  // A local build can override the version directory without CI's
  // deployment metadata. Keep its version catalogue under the same project.
  const deploymentRoot = process.env.PERFCHECKER_DOCS_BASE
    ? config.base.replace(/\/[^/]+\/$/, '')
    : 'REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'.replace(/\/$/, '')
  config.head = [
    ['script', { src: `${deploymentRoot}/versions.js` }],
    ['script', { src: `${config.base}siteinfo.js` }],
  ]
}

config.transformHead = ({ pageData }) => {
  const page = pageData.relativePath.replace(/\.md$/, '.html').replace(/^index\.html$/, '')
  const canonical = new URL(config.base + page, docsURL.origin).href
  return [
    ['link', { rel: 'canonical', href: canonical }],
    ['meta', { property: 'og:url', content: canonical }],
    ['meta', { property: 'og:title', content: pageData.title || 'PerfChecker.jl' }],
    ['meta', { property: 'og:type', content: 'website' }],
  ]
}
config.head!.push(['link', { rel: 'icon', href: `${config.base}assets/perfchecker-mark.png` }])
config.sitemap = { hostname: new URL(config.base, docsURL.origin).href }

// Keep the whole documentation visible from every page.
const sidebar = config.themeConfig?.sidebar
if (Array.isArray(sidebar)) {
  // Already-rendered Julia docstrings share this site's theme, search and base.
  const optionalNavigation = fileURLToPath(new URL('../optional-api/navigation.json', import.meta.url))
  if (existsSync(optionalNavigation)) {
    const optional = JSON.parse(readFileSync(optionalNavigation, 'utf8'))
    if (!/^[a-f0-9]{40}$/.test(optional.source_revision) || optional.owners.length !== 6)
      throw new Error('Invalid optional API navigation provenance')
    const apiGroup = sidebar.find(group => group.text === 'API')
    const companions = apiGroup?.items?.find(item => item.text === 'Companion APIs')
    if (!companions) throw new Error('Companion APIs must be nested in the API section')
    companions.collapsed = true
    companions.items = optional.owners.map(({ slug, name }) => {
      if (!/^[a-z]+$/.test(slug) || !/^PerfChecker[A-Za-z]+$/.test(name))
        throw new Error('Invalid companion API namespace')
      return { text: name, collapsed: true, items: [
        { text: 'Public API', link: `/optional-api/${slug}/public-api` },
        { text: 'Full API', link: `/optional-api/${slug}/full-api` },
      ] }
    })
  }
  for (const group of sidebar) {
    if (!group.items) continue
    group.collapsed = false
    for (const child of group.items) {
      if (child.items) child.collapsed = group.text === 'Tools' || group.text === 'API'
    }
  }
}
export default config
