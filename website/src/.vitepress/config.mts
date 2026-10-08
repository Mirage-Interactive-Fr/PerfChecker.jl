import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'
import { existsSync, readFileSync, readdirSync } from 'node:fs'
import { resolve, sep } from 'node:path'
import { createHash } from 'node:crypto'

const docsVersion = process.env.PERFCHECKER_DOCS_VERSION ?? '1.0.0'
const docsURL = new URL(process.env.PERFCHECKER_DOCS_URL ?? 'https://perfchecker.mirageinteractive.fr/')
if (docsURL.protocol !== 'https:' || docsURL.username || docsURL.password || docsURL.search || docsURL.hash)
  throw new Error('Documentation deployment URL must be plain HTTPS')
const sftp = (process.env.PERFCHECKER_DOCS_HOSTING ??
  (docsURL.origin === 'https://perfchecker.mirageinteractive.fr' ? 'sftp' : 'github')) === 'sftp'
const docsChannel = process.env.PERFCHECKER_DOCS_CHANNEL ?? 'stable'

// Both the generated VitePress config and the source config run from website/.
const mediaRoot = resolve(process.cwd(), 'src/public')
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
      { text: 'Manual', link: '/guide/overview' },
      { text: 'Examples', items: [
        { text: 'Choose an example', link: '/real-packages/' },
        { text: 'Bibliography', link: '/tutorials/bibliography' },
        { text: 'DataStructures', link: '/real-packages/datastructures' },
        { text: 'Oxygen', link: '/real-packages/oxygen' },
      ] },
      { text: 'Interfaces', items: [
        { text: 'Choose an interface', link: '/interfaces/packages' },
        { text: 'VS Code', link: '/interfaces/vscode' },
        { text: 'VS Code configuration', link: '/interfaces/vscode-configuration' },
        { text: 'Notebooks and Julia tools', link: '/interfaces/vscode-workflows' },
        { text: 'MCP advice and implementation', link: '/mcp-advisor' },
        { text: 'Web interface (Oxygen)', link: '/interfaces/web-studio' },
        { text: 'REPL and Pluto', link: '/interfaces/repl-pluto' },
        { text: 'Plots', link: '/interfaces/visualization' },
        { text: 'Documenter', link: '/interfaces/documentation' },
      ] },
      { text: 'API & reference', items: [
        { text: 'Reference index', link: '/reference/' },
        { text: 'Julia API', link: '/reference/api' },
        { text: 'Command line', link: '/reference/cli' },
        { text: 'Checks and tools', link: '/reference/checks' },
        { text: 'Run bundles', link: '/reference/run-bundles' },
        { text: 'Comparison options', link: '/reference/comparisons' },
      ] },
      { text: 'More', items: [
        { text: 'Further topics', items: [
          { text: 'Experiments', link: '/experiments' },
          { text: 'Native profiling', link: '/native-profiling' },
          { text: 'Network traffic', link: '/network-measurement' },
          { text: 'Remote workers', link: '/operations/hosted' },
          { text: 'Optional advisors', link: '/advisors' },
        ] },
        { text: 'Contributing', items: [
        { text: 'Architecture', link: '/architecture-roadmap' },
        { text: 'Report an issue', link: 'https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues' },
        { text: 'Contributing documentation', link: '/contributing/documentation' },
        { text: 'Contribute an example', link: '/real-packages/contributing' },
        ] },
      ] },
      { component: 'VersionPicker' },
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
  for (const group of sidebar) {
    if (!group.items) continue
    group.collapsed = false
    for (const child of group.items) if (child.items) child.collapsed = false
  }
}
export default config
