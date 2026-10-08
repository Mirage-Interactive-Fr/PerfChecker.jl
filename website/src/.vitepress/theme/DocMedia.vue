<script setup lang="ts">
import { withBase } from 'vitepress'
import { computed, ref } from 'vue'
declare const __PERFCHECKER_MEDIA__: Record<string, {
  file: string; local_available: boolean; youtube_id: string; download_url: string
}>
declare const __PERFCHECKER_IMAGES__: Record<string, { width: number; height: number }>
const props = defineProps<{
  src: string
  alt: string
  caption: string
  video?: boolean
  poster?: string
  subtitles?: string
  recording?: string
  preload?: 'none' | 'metadata'
  short?: boolean
  walkthrough?: string
  chapter?: string
  external?: boolean
}>()
const entry = computed(() => props.recording ? __PERFCHECKER_MEDIA__[props.recording] : undefined)
const dimensions = computed(() => __PERFCHECKER_IMAGES__[props.video ? props.poster ?? '' : props.src])
const geometry = computed(() => dimensions.value ? {
  '--doc-media-ratio': dimensions.value.width / dimensions.value.height,
  'aspect-ratio': `${dimensions.value.width} / ${dimensions.value.height}`,
} : undefined)
const mediaState = computed(() => entry.value?.youtube_id ? 'youtube' :
  props.external && entry.value?.download_url?.startsWith('https://') ? 'external' :
    entry.value?.local_available ? 'local' : 'pending')
const videoSource = computed(() => mediaState.value === 'external' ? entry.value!.download_url : withBase(props.src))
const playYouTube = ref(false)
const mediaType = computed(() => props.src.endsWith('.mp4') ? 'video/mp4' : 'video/webm')
</script>

<template>
  <figure class="doc-screenshot" :data-recording="recording" :data-media-state="video ? mediaState : undefined">
    <video v-if="video && (mediaState === 'local' || mediaState === 'external')" controls playsinline :preload="preload ?? 'none'"
      :class="{ 'doc-short-video': short }"
      :width="dimensions?.width" :height="dimensions?.height" :style="geometry"
      :aria-label="alt" :poster="poster ? withBase(poster) : undefined">
      <source :src="videoSource" :type="mediaType" />
      <track v-if="subtitles" kind="captions" :src="withBase(subtitles)"
        srclang="en" label="English walkthrough" default />
      <a :href="videoSource">Download the recording</a>.
    </video>
    <template v-else-if="video && mediaState === 'youtube'">
      <iframe v-if="playYouTube" class="doc-video" :title="alt"
        :style="geometry"
        :src="`https://www.youtube-nocookie.com/embed/${entry.youtube_id}?cc_load_policy=1`"
        referrerpolicy="strict-origin-when-cross-origin" allow="encrypted-media; picture-in-picture; fullscreen"
        allowfullscreen />
      <button v-else class="doc-video-button" type="button" @click="playYouTube = true">
        <img v-if="poster" :src="withBase(poster)" :alt="alt" :width="dimensions?.width" :height="dimensions?.height" loading="lazy" />
        <span>Watch the walkthrough on YouTube</span>
      </button>
    </template>
    <div v-else-if="video" class="doc-video-pending">
      <img v-if="poster" :src="withBase(poster)" :alt="alt" :width="dimensions?.width" :height="dimensions?.height" loading="lazy" />
      <p v-if="entry?.download_url">Download the recording below to watch it now, or follow the written walkthrough below.</p>
      <p v-else>This build has no embedded recording. Follow the written walkthrough below.</p>
    </div>
    <a v-else :href="withBase(src)" :aria-label="`Open full-size image: ${alt}`">
      <img :src="withBase(src)" :alt="alt" :width="dimensions?.width" :height="dimensions?.height" loading="lazy" />
    </a>
    <figcaption>{{ caption }}</figcaption>
    <p v-if="video && walkthrough"><a :href="withBase(walkthrough)">Full walkthrough<span v-if="chapter"> · {{ chapter }}</span></a></p>
    <p v-if="video && entry?.download_url"><a :href="entry.download_url">Download the original recording</a></p>
  </figure>
</template>

<style scoped>
.doc-screenshot {
  container-type: inline-size;
}
.doc-screenshot img, .doc-screenshot video {
  height: auto;
}
.doc-short-video {
  width: min(100%, calc(36rem * var(--doc-media-ratio, 0.5625)));
  max-width: 100%;
  max-height: 36rem;
  margin-inline: auto;
  object-fit: contain;
  background: var(--vp-c-bg-alt);
}
.doc-short-video::cue {
  font-size: clamp(10px, 3.5cqw, 13px);
  line-height: 1.25;
}
@media (max-width: 767px) {
  .doc-short-video {
    width: min(100%, calc(30rem * var(--doc-media-ratio, 0.5625)));
    max-height: 30rem;
  }
}
</style>
