import type { Theme } from 'vitepress'
import { h } from 'vue'
import DefaultTheme from 'vitepress/theme'
// DocumenterVitepress supplies these components in the generated source tree.
import VersionPicker from '../../components/VersionPicker.vue'
import SidebarDrawerToggle from '../../components/SidebarDrawerToggle.vue'
import { enhanceAppWithTabs } from 'vitepress-plugin-tabs/client'
import './style.css'
import MeasuredPlot from './MeasuredPlot.vue'
import DocMedia from './DocMedia.vue'
import HistoricalPlots from './HistoricalPlots.vue'
import MeasuredProfiles from './MeasuredProfiles.vue'
import HomeMeasurements from './HomeMeasurements.vue'
import MaintainerLink from './MaintainerLink.vue'

export default {
  extends: DefaultTheme,
  Layout() {
    return h(DefaultTheme.Layout, null, {
      'nav-bar-content-before': () => h(SidebarDrawerToggle),
    })
  },
  enhanceApp({ app }) {
    enhanceAppWithTabs(app)
    app.component('VersionPicker', VersionPicker)
    app.component('MeasuredPlot', MeasuredPlot)
    app.component('DocMedia', DocMedia)
    app.component('HistoricalPlots', HistoricalPlots)
    app.component('MeasuredProfiles', MeasuredProfiles)
    app.component('HomeMeasurements', HomeMeasurements)
    app.component('MaintainerLink', MaintainerLink)
  },
} satisfies Theme
