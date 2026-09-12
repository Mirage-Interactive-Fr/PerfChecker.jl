<script setup lang="ts">
import { withBase } from 'vitepress'
import { computed, ref } from 'vue'
declare const __PERFCHECKER_MEDIA__: Record<string, {
  file: string; local_available: boolean; youtube_id: string; download_url: string
}>
const props = defineProps<{
  src: string
  alt: string
  caption: string
  video?: boolean
  poster?: string
  subtitles?: string
  recording?: string
}>()
const entry = computed(() => props.recording ? __PERFCHECKER_MEDIA__[props.recording] : undefined)
const mediaState = computed(() => entry.value?.youtube_id ? 'youtube' : entry.value?.local_available ? 'local' : 'pending')
const playYouTube = ref(false)
</script>

<template>
  <figure class="doc-screenshot" :data-recording="recording" :data-media-state="video ? mediaState : undefined">
    <video v-if="video && mediaState === 'local'" controls playsinline preload="none"
      :aria-label="alt" :poster="poster ? withBase(poster) : undefined">
      <source :src="withBase(src)" type="video/webm" />
      <track v-if="subtitles" kind="captions" :src="withBase(subtitles)"
        srclang="en" label="English walkthrough" default />
      <a :href="withBase(src)">Download the recording</a>.
    </video>
    <template v-else-if="video && mediaState === 'youtube'">
      <iframe v-if="playYouTube" class="doc-video" :title="alt"
        :src="`https://www.youtube-nocookie.com/embed/${entry.youtube_id}?cc_load_policy=1`"
        referrerpolicy="strict-origin-when-cross-origin" allow="encrypted-media; picture-in-picture; fullscreen"
        allowfullscreen />
      <button v-else class="doc-video-button" type="button" @click="playYouTube = true">
        <img v-if="poster" :src="withBase(poster)" :alt="alt" loading="lazy" />
        <span>Watch the walkthrough on YouTube</span>
      </button>
    </template>
    <div v-else-if="video" class="doc-video-pending">
      <img v-if="poster" :src="withBase(poster)" :alt="alt" loading="lazy" />
      <p v-if="entry?.download_url">Download the recording below to watch it now. The YouTube player will be added when available. Follow the written walkthrough below.</p>
      <p v-else>The recording will be added here after publication. Follow the written walkthrough below.</p>
    </div>
    <a v-else :href="withBase(src)" :aria-label="`Open full-size image: ${alt}`">
      <img :src="withBase(src)" :alt="alt" loading="lazy" />
    </a>
    <figcaption>{{ caption }}</figcaption>
    <p v-if="video && entry?.download_url"><a :href="entry.download_url">Download the original recording</a></p>
  </figure>
</template>
