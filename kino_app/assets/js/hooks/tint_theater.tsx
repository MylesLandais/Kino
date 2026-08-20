import React from "react"
import {createRoot, type Root} from "react-dom/client"

import {TintTheaterApp} from "../theater/TintTheaterApp"

export default {
  mounted() {
    const el = this.el as HTMLElement
    const authToken = el.dataset.authToken || (el.getAttribute("data-auth-token") as string | null)
    const root: Root = createRoot(el)
    ;(this as any)._tintRoot = root
    root.render(
      <React.StrictMode>
        <TintTheaterApp authToken={authToken} />
      </React.StrictMode>,
    )
  },
  destroyed() {
    const root: Root | undefined = (this as any)._tintRoot
    root?.unmount()
  },
}
