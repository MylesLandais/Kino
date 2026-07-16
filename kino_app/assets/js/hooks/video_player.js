import Plyr from "../../vendor/plyr/plyr.mjs"

const STATE_MAP = {
  playing: "playing",
  pause: "paused",
  waiting: "buffering",
  error: "error",
  ended: "paused",
}

export default {
  mounted() {
    this.video = this.el.querySelector("video")
    this.revision = null
    this.loadedSrc = null
    this.commandedDesired = null
    this.desired = "idle"
    this.seeking = false
    this.resumeAfterSeek = false
    this.listenerId = this.getListenerId()

    this.player = new Plyr(this.video, {
      controls: [
        "play-large", "play", "progress", "current-time", "duration",
        "mute", "volume", "settings", "fullscreen",
      ],
      settings: ["speed"],
      iconUrl: "/images/plyr.svg",
      blankVideo: "",
      // Chapters later: markers: {enabled: true, points: [...]} from yt-dlp metadata
      ratio: null,
      fullscreen: {enabled: true, iosNative: true, container: "#theater-video-wrap"},
    })

    this.handleEvent("seek", ({position}) => {
      this.video.currentTime = Number(position) || 0
    })

    this.applyPlayback = ({src, desired, revision, position, markers}) => {
      if (!src) return
      const desiredChanged = this.desired !== desired
      this.desired = desired
      const srcChanged = this.loadedSrc !== src
      if (this.revision !== revision && srcChanged) {
        // Source swap (stream → cache or new video): keep the playhead.
        const resumeAt = this.loadedSrc ? this.video.currentTime : 0
        this.loadedSrc = src
        this.setMarkers(markers || [])
        this.video.src = src
        this.video.load()
        const target = Math.max(Number(position) || 0, resumeAt)
        if (target > 0) {
          this.video.addEventListener(
            "loadedmetadata",
            () => { this.video.currentTime = target },
            {once: true},
          )
        }
      }
      this.revision = revision

      // Position/observed-state broadcasts are informational. Reissuing the
      // same transport command here creates a feedback loop when autoplay is
      // blocked: play() rejects -> report paused -> playback broadcast -> play().
      if (desired === "playing" && (desiredChanged || srcChanged)) {
        this.commandedDesired = desired
        // Autoplay with sound may be blocked; report honestly and let controls take over
        Promise.resolve(this.player.play())
          .catch(() => this.report("paused"))
          .finally(() => setTimeout(() => { this.commandedDesired = null }, 0))
      } else if (desired === "paused" && desiredChanged) {
        this.commandedDesired = desired
        this.player.pause()
        queueMicrotask(() => { this.commandedDesired = null })
      }
    }
    this.handleEvent("playback", payload => this.applyPlayback(payload))
    this.pushEvent("playback_request", {}, payload => this.applyPlayback(payload))

    this.listeners = Object.keys(STATE_MAP).map(ev => {
      const fn = () => {
        const state = STATE_MAP[ev]
        const commanded = this.commandedDesired === state
        if (ev === "pause" && this.seeking && this.resumeAfterSeek) return
        if (ev === "playing" && !commanded) {
          this.desired = "playing"
          this.intent("playing")
        }
        if ((ev === "pause" || ev === "ended") && !commanded) {
          this.desired = "paused"
          this.intent("paused")
        }
        this.report(state)
      }
      this.video.addEventListener(ev, fn)
      return [ev, fn]
    })

    const onSeeking = () => {
      if (this.seeking) return
      this.seeking = true
      this.resumeAfterSeek = this.desired === "playing" || !this.video.paused
    }
    const onSeeked = () => {
      const shouldResume = this.resumeAfterSeek
      this.seeking = false
      this.resumeAfterSeek = false
      this.report(this.video.paused ? "paused" : "playing", true)

      if (shouldResume && this.video.paused) {
        this.commandedDesired = "playing"
        Promise.resolve(this.player.play())
          .catch(() => this.report("paused"))
          .finally(() => setTimeout(() => { this.commandedDesired = null }, 0))
      }
    }
    this.video.addEventListener("seeking", onSeeking)
    this.video.addEventListener("seeked", onSeeked)
    this.listeners.push(["seeking", onSeeking], ["seeked", onSeeked])

    this.timer = setInterval(() => {
      if (!this.video.paused && !this.video.ended) this.report("playing")
    }, 5000)
  },

  destroyed() {
    clearInterval(this.timer)
    this.listeners?.forEach(([ev, fn]) => this.video.removeEventListener(ev, fn))
    this.player?.destroy()
  },

  // Plyr injects markers once per source when duration is known; reset its
  // guard + DOM so a new tracklist renders after a source swap.
  setMarkers(points) {
    this.player.config.markers = {enabled: points.length > 0, points}
    this.el.querySelectorAll(".plyr__progress__marker").forEach(n => n.remove())
    if (this.player.elements) this.player.elements.markers = null
  },

  report(state, discontinuity = false) {
    this.pushEvent("observed_playback", {
      state,
      position: this.video.currentTime || 0,
      playback_rate: this.video.playbackRate || 1,
      listener_id: this.listenerId,
      discontinuity,
    })
  },

  intent(desired) {
    this.pushEvent("playback_intent", {desired})
  },

  getListenerId() {
    const key = "kino:listener-id"
    let id = window.localStorage.getItem(key)
    if (!id) {
      id = window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(36).slice(2)}`
      window.localStorage.setItem(key, id)
    }
    return id
  },
}
