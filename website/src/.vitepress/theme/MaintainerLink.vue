<template>
  <a class="maintainer-link" href="https://mirageinteractive.fr/"
     aria-label="Mirage Interactive — principal maintainer of PerfChecker">
    <span class="maintainer-label">Primarily maintained by</span>
    <span class="maintainer-name">Mirage Interactive <span aria-hidden="true">↗</span></span>
    <span class="maintainer-community">Open source. Contributions welcome.</span>
  </a>
</template>

<style scoped>
.maintainer-link {
  display: block; margin: 1rem 0 1.5rem auto; padding: 14px 16px; width: 190px;
  border: 1px solid var(--vp-c-divider); border-radius: 12px;
  background: var(--vp-c-bg-soft); color: var(--vp-c-text-1);
  text-decoration: none !important; line-height: 1.5;
}
.maintainer-label, .maintainer-community { display: block; color: var(--vp-c-text-2); font-size: 11px; }
.maintainer-name { display: block; margin: 5px 0; font-size: 14px; font-weight: 650; }
.maintainer-name span { color: var(--vp-c-brand-1); }
.maintainer-link:hover { border-color: var(--vp-c-brand-1); }
.maintainer-link:focus-visible { outline: 3px solid var(--vp-c-brand-1); outline-offset: 3px; }
@media (min-width: 1280px) {
  .maintainer-link { position: fixed; top: 92px; right: 20px; z-index: 20; margin: 0; }
}
</style>
