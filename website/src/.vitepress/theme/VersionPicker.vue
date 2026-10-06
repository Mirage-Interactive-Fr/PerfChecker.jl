<script setup lang="ts">
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useData } from 'vitepress'
import VPNavBarMenuGroup from 'vitepress/dist/client/theme-default/components/VPNavBarMenuGroup.vue'
import VPNavScreenMenuGroup from 'vitepress/dist/client/theme-default/components/VPNavScreenMenuGroup.vue'

declare global {
  interface Window {
    DOC_VERSIONS?: string[]
    DOCUMENTER_CURRENT_VERSION?: string
    DOC_VERSION_URLS?: Record<string, string>
  }
}

declare const __PERFCHECKER_DOCS_VERSION__: string

defineProps<{ screenMenu?: boolean }>()
const { site } = useData()
const base = site.value.base
const directory = base.split('/').filter(Boolean).at(-1)
const versionDirectory = directory && /^(dev|stable|v\d+(?:\.\d+)*(?:-[\w.-]+)?)$/.test(directory)
const root = versionDirectory ? base.slice(0, -(directory.length + 1)) : base
const currentVersion = ref(versionDirectory ? directory : __PERFCHECKER_DOCS_VERSION__)
const versions = ref<Array<{ text: string, link: string }>>([])
const ready = ref(false)
let timer: ReturnType<typeof setInterval> | undefined

function readMetadata() {
  const catalogue = window.DOC_VERSIONS
  const current = window.DOCUMENTER_CURRENT_VERSION
  if (!catalogue?.length || !current) return false
  currentVersion.value = current
  versions.value = catalogue.map(version => ({
    text: version,
    link: new URL(window.DOC_VERSION_URLS?.[version] ?? `${root}${encodeURIComponent(version)}/`, window.location.origin).href,
  }))
  return true
}

onMounted(() => {
  versions.value = [{ text: currentVersion.value, link: new URL(base, window.location.origin).href }]
  ready.value = true
  if (readMetadata()) return
  // Documenter supplies these scripts separately from the tested site artifact.
  // A standalone build still links to its own configured version directory.
  const deadline = Date.now() + 5000
  timer = setInterval(() => {
    if (readMetadata() || Date.now() >= deadline) clearInterval(timer)
  }, 100)
})
onUnmounted(() => clearInterval(timer))
const versionItems = computed(() => versions.value)
</script>

<template>
  <template v-if="ready">
    <VPNavBarMenuGroup
      v-if="!screenMenu"
      :item="{ text: currentVersion, items: versionItems }"
      class="VPVersionPicker"
    />
    <VPNavScreenMenuGroup
      v-else
      :text="currentVersion"
      :items="versionItems"
      class="VPVersionPicker"
    />
  </template>
</template>
