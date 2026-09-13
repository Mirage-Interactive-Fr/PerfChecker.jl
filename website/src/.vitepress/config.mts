import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'
import { existsSync, readFileSync } from 'node:fs'
import { resolve, sep } from 'node:path'
import { createHash } from 'node:crypto'

// Both the generated VitePress config and the source config run from website/.
const mediaRoot = resolve(process.cwd(), 'src/public')
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

const config = defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  lastUpdated: true,
  cleanUrls: true,
  vite: { define: {
    __PERFCHECKER_MEDIA__: JSON.stringify(media),
    __DEPLOY_ABSPATH__: JSON.stringify('REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'),
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
    logo: '/assets/perfchecker.svg',
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
        { text: 'Web Studio', link: '/interfaces/web-studio' },
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
      pattern: 'https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/edit/release/v1.0.0-rc1/website/src/:path',
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

// Documenter's deployment provides both files. Local previews have only this
// development build, so do not request a nonexistent publication catalogue.
if (config.base !== '/') {
  const deploymentRoot = 'REPLACE_ME_DOCUMENTER_VITEPRESS_DEPLOY_ABSPATH'.replace(/\/$/, '')
  config.head = [
    ['script', { src: `${deploymentRoot}/versions.js` }],
    ['script', { src: `${config.base}siteinfo.js` }],
  ]
}

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
