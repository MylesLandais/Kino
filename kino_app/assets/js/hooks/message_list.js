export default {
  mounted() {
    this.scrollToLatest()
  },

  updated() {
    this.scrollToLatest()
  },

  scrollToLatest() {
    requestAnimationFrame(() => {
      this.el.scrollTo({top: this.el.scrollHeight, behavior: "smooth"})
    })
  },
}
