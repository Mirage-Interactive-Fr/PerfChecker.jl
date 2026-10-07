import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'
import { existsSync, readFileSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve, sep } from 'node:path'
import { createHash } from 'node:crypto'
import { fileURLToPath } from 'node:url'

const docsVersion = process.env.PERFCHECKER_DOCS_VERSION ?? '1.0.0'
const docsURL = new URL(process.env.PERFCHECKER_DOCS_URL ?? 'https://perfchecker.mirageinteractive.fr/')
if (docsURL.protocol !== 'https:' || docsURL.username || docsURL.password || docsURL.search || docsURL.hash)
  throw new Error('Documentation deployment URL must be plain HTTPS')
const sftp = (process.env.PERFCHECKER_DOCS_HOSTING ??
  (docsURL.origin === 'https://perfchecker.mirageinteractive.fr' ? 'sftp' : 'github')) === 'sftp'
const docsChannel = process.env.PERFCHECKER_DOCS_CHANNEL ?? 'stable'

// Use this config's public tree: Documenter has already copied the source tree
// when VitePress loads its generated config. Fetched assets must enter that copy.
const mediaRoot = resolve(fileURLToPath(new URL('../public/', import.meta.url)))
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
