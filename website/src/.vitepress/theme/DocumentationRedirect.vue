<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { withBase } from 'vitepress'
const props = defineProps<{ target: string; fragments?: Record<string, string> }>()
const destination = ref(props.target)
onMounted(() => {
  let fragment = location.hash.slice(1)
  try { fragment = decodeURIComponent(fragment) } catch { /* Preserve malformed old links. */ }
  destination.value = props.fragments?.[fragment] ?? props.target
  location.replace(withBase(destination.value))
})
</script>
<template><p>This chapter has moved. <a :href="withBase(destination)">Continue reading</a>.</p></template>
