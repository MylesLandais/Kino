import { useEffect, useRef, useState } from 'react'
import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { VRMLoaderPlugin, VRMUtils } from '@pixiv/three-vrm'
import type { VRM } from '@pixiv/three-vrm'

const MODEL_URL =
  'https://raw.githubusercontent.com/pixiv/three-vrm/dev/packages/three-vrm/examples/models/VRM1_Constraint_Twist_Sample.vrm'

const W = 220
const H = 320

interface Props {
  visible: boolean
}

export function VRMOverlay({ visible }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const vrmRef = useRef<VRM | null>(null)
  const clockRef = useRef(new THREE.Clock())
  const rafRef = useRef<number>(0)
  const [status, setStatus] = useState<'loading' | 'ready' | 'error'>('loading')
  const [pos, setPos] = useState({ x: 16, y: 16 })
  const dragging = useRef<{ ox: number; oy: number } | null>(null)

  useEffect(() => {
    const canvas = canvasRef.current
    if (!canvas) return

    // Renderer with alpha so only avatar shows over video
    const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true })
    renderer.setSize(W, H)
    renderer.setPixelRatio(window.devicePixelRatio)
    renderer.setClearColor(0x000000, 0)

    const scene = new THREE.Scene()

    const camera = new THREE.PerspectiveCamera(30, W / H, 0.1, 20)
    camera.position.set(0, 1.3, 2.8)
    camera.lookAt(0, 1.2, 0)

    // Soft lighting — warm rim + cool fill
    const ambient = new THREE.AmbientLight(0xffffff, 0.6)
    scene.add(ambient)

    const rim = new THREE.DirectionalLight(0x957fb8, 1.2) // oni-violet rim
    rim.position.set(-1.5, 2, -1)
    scene.add(rim)

    const fill = new THREE.DirectionalLight(0x7fb4ca, 0.8) // spring-blue fill
    fill.position.set(1, 1.5, 2)
    scene.add(fill)

    const loader = new GLTFLoader()
    loader.register(parser => new VRMLoaderPlugin(parser))

    loader.load(
      MODEL_URL,
      gltf => {
        const vrm: VRM = gltf.userData.vrm
        VRMUtils.removeUnnecessaryVertices(gltf.scene)
        VRMUtils.combineSkeletons(gltf.scene)
        vrm.scene.rotation.y = Math.PI // face camera
        scene.add(vrm.scene)
        vrmRef.current = vrm
        setStatus('ready')
      },
      undefined,
      err => {
        console.error('VRM load error', err)
        setStatus('error')
      },
    )

    let t = 0
    const animate = () => {
      rafRef.current = requestAnimationFrame(animate)
      const delta = clockRef.current.getDelta()
      t += delta
      const vrm = vrmRef.current
      if (vrm) {
        vrm.update(delta)

        // Idle breathing — chest
        const chest = vrm.humanoid.getNormalizedBoneNode('chest')
        if (chest) {
          chest.rotation.x = Math.sin(t * 0.8) * 0.018
        }

        // Head sway
        const head = vrm.humanoid.getNormalizedBoneNode('head')
        if (head) {
          head.rotation.y = Math.sin(t * 0.4) * 0.08
          head.rotation.z = Math.sin(t * 0.3 + 1) * 0.04
        }

        // Eye blink every ~4s
        const blinkPhase = (t % 4) / 4
        const blink = blinkPhase > 0.95 ? Math.sin((blinkPhase - 0.95) / 0.05 * Math.PI) : 0
        vrm.expressionManager?.setValue('blink', blink)

        // Gentle float
        vrm.scene.position.y = Math.sin(t * 0.6) * 0.015
      }
      renderer.render(scene, camera)
    }
    animate()

    return () => {
      cancelAnimationFrame(rafRef.current)
      renderer.dispose()
      if (vrmRef.current) {
        VRMUtils.deepDispose(vrmRef.current.scene)
        vrmRef.current = null
      }
    }
  }, [])

  // Drag handlers
  const onPointerDown = (e: React.PointerEvent) => {
    e.currentTarget.setPointerCapture(e.pointerId)
    dragging.current = { ox: e.clientX - pos.x, oy: e.clientY - pos.y }
  }
  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragging.current) return
    setPos({ x: e.clientX - dragging.current.ox, y: e.clientY - dragging.current.oy })
  }
  const onPointerUp = () => { dragging.current = null }

  if (!visible) return null

  return (
    <div
      style={{
        position: 'absolute',
        left: pos.x,
        top: pos.y,
        width: W,
        userSelect: 'none',
        zIndex: 10,
      }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
    >
      {/* Drag handle */}
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '3px 8px',
        backgroundColor: 'rgba(22,22,29,0.75)',
        border: '1px solid var(--kana-ink4)',
        borderBottom: 'none',
        cursor: 'grab',
        backdropFilter: 'blur(4px)',
      }}>
        <span style={{ fontSize: 9, color: 'var(--kana-violet)', letterSpacing: '0.1em' }}>VRM</span>
        {status === 'loading' && (
          <span style={{ fontSize: 9, color: 'var(--kana-yellow)' }}>loading…</span>
        )}
        {status === 'error' && (
          <span style={{ fontSize: 9, color: 'var(--kana-red)' }}>load failed</span>
        )}
        {status === 'ready' && (
          <span style={{ fontSize: 9, color: 'var(--kana-green)' }}>● live</span>
        )}
      </div>

      <canvas
        ref={canvasRef}
        width={W}
        height={H}
        style={{
          display: 'block',
          width: W,
          height: H,
          cursor: 'grab',
          // Subtle vignette at the bottom so avatar fades into the video
          maskImage: 'linear-gradient(to bottom, black 70%, transparent 100%)',
          WebkitMaskImage: 'linear-gradient(to bottom, black 70%, transparent 100%)',
        }}
      />
    </div>
  )
}
