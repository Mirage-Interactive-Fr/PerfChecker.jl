import type { Theme } from 'vitepress'
import { h, onMounted, onUnmounted } from 'vue'
import DefaultTheme from 'vitepress/theme'
import VersionPicker from './VersionPicker.vue'
// DocumenterVitepress supplies this component in the generated source tree.
import SidebarDrawerToggle from '../../components/SidebarDrawerToggle.vue'
import { enhanceAppWithTabs } from 'vitepress-plugin-tabs/client'
import './style.css'
import MeasuredPlot from './MeasuredPlot.vue'
import DocMedia from './DocMedia.vue'
import HistoricalPlots from './HistoricalPlots.vue'
import MeasuredProfiles from './MeasuredProfiles.vue'
import HomeMeasurements from './HomeMeasurements.vue'
import MaintainerLink from './MaintainerLink.vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
import PackageGallery from './PackageGallery.vue'
import WorkloadAtlas from './WorkloadAtlas.vue'
import RecordedFigures from './RecordedFigures.vue'
import DiagnosticReports from './DiagnosticReports.vue'

export default {
  extends: DefaultTheme,
  setup() {
    // The tabs component selects and focuses the next button itself.
    // Prevent the browser's additional horizontal scroll for these two keys.
    const preventNativeTabScroll = (event: KeyboardEvent) => {
      if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return
      if (event.target instanceof Element &&
          event.target.closest('.plugin-tabs--tab-list > [role="tab"]')) {
        event.preventDefault()
        const tablist = event.target.closest('.plugin-tabs--tab-list')!
        requestAnimationFrame(() => {
          const selected = tablist.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]')
          if (!selected || document.activeElement !== selected) return
          const bounds = tablist.getBoundingClientRect()
          const tab = selected.getBoundingClientRect()
          if (tab.right > bounds.right) tablist.scrollLeft += tab.right - bounds.right
          else if (tab.left < bounds.left) tablist.scrollLeft -= bounds.left - tab.left
        })
      }
    }
    onMounted(() => document.addEventListener('keydown', preventNativeTabScroll, true))
    onUnmounted(() => document.removeEventListener('keydown', preventNativeTabScroll, true))
  },
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
    app.component('NormalizedMeasurements', NormalizedMeasurements)
    app.component('PackageGallery', PackageGallery)
    app.component('WorkloadAtlas', WorkloadAtlas)
    app.component('RecordedFigures', RecordedFigures)
    app.component('DiagnosticReports', DiagnosticReports)
  },
} satisfies Theme
