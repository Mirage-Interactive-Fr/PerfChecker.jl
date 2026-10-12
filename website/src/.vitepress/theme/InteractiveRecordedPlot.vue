<script setup lang="ts">
import { withBase } from 'vitepress'
import { onBeforeUnmount, ref, watch } from 'vue'
import NormalizedMeasurements from './NormalizedMeasurements.vue'
const props = defineProps<{ source: string; figure?: string; title: string; kind?: string; html?: string; timeUnit?: string }>()
const frame = ref<HTMLIFrameElement | null>(null)
const frameHeight = ref(640)
let observer: ResizeObserver | undefined
let frameWindow: Window | null = null
let resizeRequest: number | undefined
function disconnectFrame() {
  observer?.disconnect()
  observer = undefined
  frameWindow?.removeEventListener('resize', scheduleFit)
  frameWindow = null
  if (resizeRequest !== undefined) cancelAnimationFrame(resizeRequest)
  resizeRequest = undefined
}
function scheduleFit() {
  if (resizeRequest !== undefined) return
  resizeRequest = requestAnimationFrame(() => {
    resizeRequest = undefined
    try {
      const body = frame.value?.contentDocument?.body
      if (!body || !frame.value?.clientWidth) return
      const height = Math.ceil(Math.max(body.scrollHeight, body.getBoundingClientRect().height))
      const viewport = frame.value.clientHeight
      // A body with min-height:100vh already includes our current viewport.
      // Do not repeatedly add padding to that self-dependent measurement.
      if (Number.isFinite(height) && height > 0 &&
          (height > viewport + 1 || height < viewport - 3)) {
        frameHeight.value = Math.max(640, height + 2)
      }
    } catch { /* Direct links remain usable for external exports. */ }
  })
}
function observeFrame() {
  disconnectFrame()
  frameHeight.value = 640
  try {
    const body = frame.value?.contentDocument?.body
    if (!body) return
    frameWindow = frame.value?.contentWindow ?? null
    frameWindow?.addEventListener('resize', scheduleFit)
    if (typeof ResizeObserver !== 'undefined') {
      observer = new ResizeObserver(scheduleFit)
      observer.observe(body)
    }
    scheduleFit()
  } catch { /* Cross-origin exports keep the fallback viewport. */ }
}
watch(() => props.html, () => { disconnectFrame(); frameHeight.value = 640 })
onBeforeUnmount(disconnectFrame)
</script>

<template>
  <NormalizedMeasurements v-if="kind === 'normalized_metrics'" :source="source"
    :figure="figure" :html="html" :package-name="title" />
  <section v-else class="recorded-export" :aria-label="title">
    <iframe v-if="html" ref="frame" :key="html" :src="withBase(html)" :title="title"
      :style="{ height: `${frameHeight}px` }" @load="observeFrame"
      loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads" />
    <a v-else-if="figure" :href="withBase(figure)"><img :src="withBase(figure)" :alt="title" loading="lazy" /></a>
    <p v-else>No saved interactive export is available.</p>
    <p v-if="html"><a :href="withBase(html)">Open the same interactive export</a></p>
    <p v-else-if="figure">Static export from the saved measurements. <a :href="withBase(figure)">Open the full-size figure</a>.</p>
    <a :href="withBase(source)" download>Download the serialized plot</a>
  </section>
</template>

<style scoped>
.recorded-export{min-width:0;border:1px solid var(--vp-c-divider);border-radius:8px;padding:.75rem;margin:.8rem 0}
iframe{display:block;width:100%;height:640px;border:0;background:white}
img{display:block;max-width:100%;height:auto;background:white}
p,a{overflow-wrap:anywhere}
@media(max-width:600px){.recorded-export{padding:.35rem}}
</style>
