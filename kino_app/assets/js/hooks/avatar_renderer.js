import AvatarEngine from "../avatar/engine"
export default {
  mounted(){
    this.status=this.el.querySelector(".avatar-loading")
    this.setState("initializing", "initializing avatar…")
    try { this.engine=new AvatarEngine(this.el.querySelector("canvas")) }
    catch(e) { this.setState("error", `renderer unavailable: ${e.message}`); console.error("Kino avatar renderer failed",e); return }
    this.engine.onGestureFinished=()=>{ this.el.dataset.avatarAnimationState="idle" }
    this.applyProfile=async profile=>{
      this.setState("loading", "loading avatar…")
      try { await this.engine.configure(profile); this.setState("ready", "") }
      catch(e) { this.setState("error", "avatar unavailable"); console.error("Kino avatar profile failed", e) }
    }
    this.handleEvent("avatar_profile", profile=>this.applyProfile(profile))
    this.handleEvent("avatar_animation", payload=>this.engine.play(payload).then(()=>{ this.el.dataset.avatarAnimation=payload.name || payload.id; this.el.dataset.avatarAnimationState="playing" }).catch(e=>{ this.setState("error", "animation unavailable"); console.error("Kino avatar animation failed",e) }))
    this.handleEvent("avatar_expression", payload=>this.engine.expression(payload))
    this.handleEvent("avatar_lip", payload=>this.engine.lip(payload))
    this.pushEvent("avatar_profile_request", {}, profile=>this.applyProfile(profile))
  },
  setState(state, label){ this.el.dataset.avatarState=state; this.status.textContent=label; this.status.hidden=!label },
  destroyed(){ this.engine?.dispose() },
}
