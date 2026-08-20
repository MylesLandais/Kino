import React from "react"
import {createRoot, type Root} from "react-dom/client"

import {TintTheaterApp} from "../theater/TintTheaterApp"

export default {
  mounted() {
    const el = this.el as HTMLElement
    const root: Root = createRoot(el)
    ;(this as any)._tintRoot = root
    root.render(
      <React.StrictMode>
        <TintTheaterApp />
      </React.StrictMode>,
    )
  },
  destroyed() {
    const root: Root | undefined = (this as any)._tintRoot
    root?.unmount()
  },
}
