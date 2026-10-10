import DefaultTheme from 'vitepress/theme'
import type { Theme } from 'vitepress'
import { enhanceAppWithTabs } from 'vitepress-plugin-tabs/client'
// DocumenterVitepress supplies the pinned renderer's docstring stylesheet.
import './docstrings.css'
import './style.css'

export default {
  extends: DefaultTheme,
  enhanceApp({ app }) {
    enhanceAppWithTabs(app)
  },
} satisfies Theme
