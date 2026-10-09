import { defineConfig } from 'vitepress'
import { tabsMarkdownPlugin } from 'vitepress-plugin-tabs'
import footnote from 'markdown-it-footnote'
import mathjax from 'markdown-it-mathjax3'

// All imports are provided by the repository's website/package-lock.json.
// This reference does not inherit the renderer template's optional Node plugins.
export default defineConfig({
  base: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  title: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  description: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  outDir: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
  cleanUrls: false,
  ignoreDeadLinks: false,
  markdown: {
    config(md) {
      md.use(tabsMarkdownPlugin)
      md.use(footnote)
      md.use(mathjax)
    },
    theme: { light: 'github-light', dark: 'github-dark' },
  },
  themeConfig: {
    nav: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    sidebar: 'REPLACE_ME_DOCUMENTER_VITEPRESS',
    outline: { level: [2, 3] },
    search: { provider: 'local' },
    socialLinks: [
      { icon: 'github', link: 'REPLACE_ME_DOCUMENTER_VITEPRESS' },
    ],
  },
})
