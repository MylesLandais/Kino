// Keeps the currently playing setlist row centered in view (maya-unified port).
export default {
  mounted() {
    this.handleEvent("share-track-link", async ({url, title}) => {
      try {
        if (navigator.share) {
          await navigator.share({title, url})
        } else {
          await navigator.clipboard.writeText(url)
          this.flashCopied()
        }
      } catch (error) {
        if (error?.name !== "AbortError") {
          await navigator.clipboard.writeText(url)
          this.flashCopied()
        }
      }
    })
  },

  flashCopied() {
    const previous = this.el.dataset.shareStatus
    this.el.dataset.shareStatus = "link copied"
    clearTimeout(this.shareTimer)
    this.shareTimer = setTimeout(() => {
      if (previous) this.el.dataset.shareStatus = previous
      else delete this.el.dataset.shareStatus
    }, 1600)
  },

  updated() {
    const row = this.el.querySelector(".track.current")
    if (!row) return
    const list = this.el
    const listRect = list.getBoundingClientRect()
    const rowRect = row.getBoundingClientRect()
    const visible = rowRect.top >= listRect.top && rowRect.bottom <= listRect.bottom
    if (!visible) row.scrollIntoView({behavior: "smooth", block: "center"})
  },
}
