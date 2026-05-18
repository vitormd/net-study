<script setup>
import MarkdownIt from 'markdown-it'
import homeMd from '../content/home.md?raw'

// Markdown estático da home — renderizado uma vez no load.
const md = new MarkdownIt({ html: false, linkify: true, typographer: true })
const html = md.render(homeMd)
</script>

<template>
  <div class="tab-view">
    <section class="home">
      <div class="markdown-body" v-html="html"></div>
    </section>
  </div>
</template>
