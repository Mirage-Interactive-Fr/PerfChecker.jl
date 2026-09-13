<script setup lang="ts">
import { withBase } from 'vitepress'
defineProps<{ directory: string; view: any }>()
</script>
<template>
  <figure>
    <h4>{{ view.title }} · {{ view.label }}</h4>
    <img :src="withBase(directory+'/'+view.svg)" :alt="view.title+' '+view.label" loading="lazy" />
    <figcaption><a :href="withBase(directory+'/'+view.json)">Recorded data</a> · <a :href="withBase(directory+'/'+view.terminal)">Unicode view</a> · <a :href="withBase(directory+'/'+view.svg)">Full-size figure</a></figcaption>
  </figure>
</template>
<style scoped>figure{margin:1rem 0 2rem}img{width:100%;background:white;border-radius:8px}</style>
