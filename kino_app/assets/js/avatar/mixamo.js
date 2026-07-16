import * as THREE from "three"
import {FBXLoader} from "three/addons/loaders/FBXLoader.js"

const BONES = {
  mixamorigHips:"hips", mixamorigSpine:"spine", mixamorigSpine1:"chest", mixamorigSpine2:"upperChest",
  mixamorigNeck:"neck", mixamorigHead:"head", mixamorigLeftShoulder:"leftShoulder",
  mixamorigLeftArm:"leftUpperArm", mixamorigLeftForeArm:"leftLowerArm", mixamorigLeftHand:"leftHand",
  mixamorigRightShoulder:"rightShoulder", mixamorigRightArm:"rightUpperArm", mixamorigRightForeArm:"rightLowerArm",
  mixamorigRightHand:"rightHand", mixamorigLeftUpLeg:"leftUpperLeg", mixamorigLeftLeg:"leftLowerLeg",
  mixamorigLeftFoot:"leftFoot", mixamorigLeftToeBase:"leftToes", mixamorigRightUpLeg:"rightUpperLeg",
  mixamorigRightLeg:"rightLowerLeg", mixamorigRightFoot:"rightFoot", mixamorigRightToeBase:"rightToes",
}
for (const side of ["Left", "Right"]) for (const [mix, vrm] of [["Thumb1","ThumbMetacarpal"],["Thumb2","ThumbProximal"],["Thumb3","ThumbDistal"],["Index1","IndexProximal"],["Index2","IndexIntermediate"],["Index3","IndexDistal"],["Middle1","MiddleProximal"],["Middle2","MiddleIntermediate"],["Middle3","MiddleDistal"],["Ring1","RingProximal"],["Ring2","RingIntermediate"],["Ring3","RingDistal"],["Pinky1","LittleProximal"],["Pinky2","LittleIntermediate"],["Pinky3","LittleDistal"]]) BONES[`mixamorig${side}Hand${mix}`] = `${side.toLowerCase()}${vrm}`

export const mixamoKey = name => String(name || "").replace(/^mixamorig:/i, "mixamorig")
export async function loadMixamo(vrm, url) {
  const asset = await new FBXLoader().loadAsync(url)
  const source = THREE.AnimationClip.findByName(asset.animations, "mixamo.com") || asset.animations[0]
  if (!source) return null
  const nodes = new Map(); asset.traverse(node => { const key = mixamoKey(node.name); if (key.startsWith("mixamorig") && !nodes.has(key)) nodes.set(key, node) })
  const tracks = [], rest = new THREE.Quaternion(), parent = new THREE.Quaternion(), q = new THREE.Quaternion()
  const isVrm0 = vrm.meta?.metaVersion === "0"
  const motionHips = nodes.get("mixamorigHips")?.position?.y
  const vrmHips = vrm.humanoid?.normalizedRestPose?.hips?.position?.[1]
  const scale = motionHips > 0 && vrmHips > 0 ? vrmHips / motionHips : 1
  for (const track of source.tracks) {
    const dot = track.name.indexOf("."); if (dot < 0) continue
    const key = mixamoKey(track.name.slice(0, dot)), property = track.name.slice(dot + 1), bone = BONES[key]
    const target = bone && vrm.humanoid.getNormalizedBoneNode(bone), sourceNode = nodes.get(key)
    if (!target || !sourceNode?.parent) continue
    sourceNode.getWorldQuaternion(rest).invert(); sourceNode.parent.getWorldQuaternion(parent)
    if (track instanceof THREE.QuaternionKeyframeTrack) {
      const values = track.values.slice(); for (let i=0;i<values.length;i+=4) { q.fromArray(values,i).premultiply(parent).multiply(rest).toArray(values,i) }
      tracks.push(new THREE.QuaternionKeyframeTrack(`${target.name}.${property}`, track.times, values.map((v,i) => isVrm0 && i%2===0 ? -v : v)))
    } else if (track instanceof THREE.VectorKeyframeTrack) {
      tracks.push(new THREE.VectorKeyframeTrack(`${target.name}.${property}`, track.times, track.values.map((v,i) => { const n=v*scale; return isVrm0 && i%3!==1 ? -n : n })))
    }
  }
  return tracks.length ? new THREE.AnimationClip("kino_mixamo", source.duration, tracks) : null
}
