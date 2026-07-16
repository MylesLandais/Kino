import * as THREE from "three"
import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js"
import {VRMLoaderPlugin, VRMUtils} from "@pixiv/three-vrm"
import {loadMixamo} from "./mixamo"

export default class AvatarEngine {
  constructor(canvas) {
    this.canvas=canvas; this.renderer=new THREE.WebGLRenderer({canvas,alpha:true,antialias:true,powerPreference:"high-performance"}); this.renderer.outputColorSpace=THREE.SRGBColorSpace; this.renderer.setClearColor(0,0)
    this.scene=new THREE.Scene(); this.camera=new THREE.PerspectiveCamera(28,1,.05,30); this.scene.add(new THREE.HemisphereLight(0xffffff,0x444466,1)); const key=new THREE.DirectionalLight(0xffffff,1); key.position.set(1,2,2); this.scene.add(key)
    this.loader=new GLTFLoader(); this.loader.register(parser=>new VRMLoaderPlugin(parser)); this.clock=new THREE.Clock(); this.mixer=null; this.idle=null; this.gesture=null; this.raf=0
    this.resizeObserver=new ResizeObserver(()=>this.resize()); this.resizeObserver.observe(canvas.parentElement); this.resize(); this.tick()
  }
  async configure(profile) {
    this.profile=profile; if (!profile?.enabled || !profile.model?.url) { this.canvas.parentElement.hidden=true; return }
    this.canvas.parentElement.hidden=false
    if (this.modelId !== profile.model.id) await this.loadModel(profile.model)
  }
  async loadModel(model) {
    this.clearGesture(); this.idle?.stop(); this.idle=null
    if (this.vrm) { this.scene.remove(this.vrm.scene); VRMUtils.deepDispose(this.vrm.scene) }
    const gltf=await this.loader.loadAsync(model.url), vrm=gltf.userData.vrm; if (!vrm) throw new Error("Not a VRM model")
    try { VRMUtils.rotateVRM0(vrm) } catch (_) {}
    this.scene.add(vrm.scene); this.vrm=vrm; this.modelId=model.id; this.mixer=new THREE.AnimationMixer(vrm.scene)
    const box=new THREE.Box3().setFromObject(vrm.scene), size=box.getSize(new THREE.Vector3()), center=box.getCenter(new THREE.Vector3()), dist=Math.max(Number(this.profile.camera_distance)||1.8,size.y*1.35)
    this.camera.position.set(center.x,center.y+size.y*.05,center.z+dist); this.camera.lookAt(center)
    if (this.profile.look_at_camera && vrm.lookAt) { vrm.lookAt.target=new THREE.Object3D(); vrm.lookAt.target.position.copy(this.camera.position); this.scene.add(vrm.lookAt.target) }
    if (this.profile.idle?.url) { const clip=await loadMixamo(vrm,this.profile.idle.url); if (clip) { this.idle=this.mixer.clipAction(clip); this.idle.setLoop(THREE.LoopRepeat,Infinity).play() } }
  }
  async play(payload) {
    if (!this.vrm || !payload?.url) return
    const clip=await loadMixamo(this.vrm,payload.url); if (!clip) return
    this.clearGesture(); const action=this.mixer.clipAction(clip); action.setLoop(payload.loop?THREE.LoopRepeat:THREE.LoopOnce,payload.loop?Infinity:1); action.clampWhenFinished=!payload.loop; this.idle?.crossFadeTo(action,.3,true); action.play(); this.gesture=action
    if (!payload.loop) { this.finished=e=>{ if(e.action!==action)return; action.fadeOut(.35); if(this.idle){this.idle.reset().setEffectiveTimeScale(1).setEffectiveWeight(1).fadeIn(.35).play()} this.clearGesture(); this.onGestureFinished?.(payload) }; this.mixer.addEventListener("finished",this.finished) }
  }
  expression({mood}) { if (this.vrm?.expressionManager && mood) { this.vrm.expressionManager.resetValues(); this.vrm.expressionManager.setValue(mood,1) } }
  lip({level=0}) { this.vrm?.expressionManager?.setValue("aa",Math.min(1,Number(level)*6)) }
  resize(){ const p=this.canvas.parentElement,w=Math.max(1,p.clientWidth),h=Math.max(1,p.clientHeight); this.renderer.setSize(w,h,false); this.camera.aspect=w/h; this.camera.updateProjectionMatrix() }
  tick(){ this.raf=requestAnimationFrame(()=>this.tick()); const d=Math.min(this.clock.getDelta(),.1); this.mixer?.update(d); this.vrm?.update(d); this.renderer.render(this.scene,this.camera) }
  clearGesture(){ if(this.finished&&this.mixer)this.mixer.removeEventListener("finished",this.finished); this.finished=null; this.gesture?.stop(); this.gesture=null }
  dispose(){ cancelAnimationFrame(this.raf); this.resizeObserver.disconnect(); this.clearGesture(); if(this.vrm)VRMUtils.deepDispose(this.vrm.scene); this.renderer.dispose() }
}
