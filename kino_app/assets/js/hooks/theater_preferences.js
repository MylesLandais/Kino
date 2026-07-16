const MODE_KEY = "kino:setlist-mode"

export default {
  mounted() {
    const mode = window.localStorage.getItem(MODE_KEY)
    if (mode === "push") this.pushEvent("set_setlist_mode", {mode})

    this.handleEvent("setlist_preference", ({mode}) => {
      if (mode === "overlay" || mode === "push") window.localStorage.setItem(MODE_KEY, mode)
    })
  },
}
