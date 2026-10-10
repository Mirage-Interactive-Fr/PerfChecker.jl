<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { withBase } from 'vitepress'
const props = withDefaults(defineProps<{ source?: string; figure?: string; html?: string; packageName?: string; compact?: boolean }>(), {
  source: '/examples/bibliography/history/normalized.json', packageName: 'Bibliography'
})
const interactive = computed(() => props.html ??
  (props.source === '/examples/bibliography/history/normalized.json'
    ? '/examples/bibliography/history/normalized.html' : ''))
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
      if (!body) return
      // Native exports keep a bounded plot viewport; measure the body, not the
      // iframe's document element, whose height would include our own viewport.
      const height = Math.ceil(Math.max(body.scrollHeight, body.getBoundingClientRect().height))
      if (Number.isFinite(height) && height > 0) frameHeight.value = Math.max(640, height + 2)
    } catch { /* Keep the fallback height if this is not a same-origin export. */ }
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
  } catch { /* External exports can still be opened through their direct link. */ }
}
watch(interactive, () => { disconnectFrame(); frameHeight.value = 640 })
onBeforeUnmount(disconnectFrame)
</script>

<template>
  <section class="normalized-measurements" :aria-label="`${packageName} saved measurements`">
    <iframe v-if="interactive" ref="frame" :key="interactive" :src="withBase(interactive)"
      :title="`${packageName}: public PerfChecker interactive export`"
      :style="{ height: `${frameHeight}px` }" @load="observeFrame"
      loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads" />
    <a v-else-if="figure" :href="withBase(figure)"><img :src="withBase(figure)"
      :alt="`${packageName}: static PerfChecker plot of the saved measurements`" loading="lazy" /></a>
    <p v-else>No saved interactive or static export is available.</p>
    <p v-if="!compact" class="normalization-note">Each curve has its own reference at <strong>1</strong>. Read the statistic, reference, units and unavailable values in the exported plot before comparing curves.</p>
    <p class="export-links"><a v-if="interactive" :href="withBase(interactive)">Open the same interactive export</a><span v-if="interactive"> · </span><a :href="withBase(source)" download>Download the serialized plot</a><template v-if="figure"> · <a :href="withBase(figure)">Open the static SVG</a></template></p>
  </section>
</template>

<style scoped>
.normalized-measurements{min-width:0;border:1px solid var(--vp-c-divider);border-radius:10px;padding:.75rem;margin:1.4rem 0}
iframe{display:block;width:100%;height:640px;border:0;background:white;border-radius:6px}
img{display:block;max-width:100%;height:auto;background:white}
.normalization-note,.export-links{font-size:.85rem;line-height:1.6;overflow-wrap:anywhere}
@media(max-width:600px){.normalized-measurements{padding:.35rem}}
</style>
