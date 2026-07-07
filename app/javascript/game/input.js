const KEYMAP = {
  KeyW: "up", ArrowUp: "up",
  KeyS: "down", ArrowDown: "down",
  KeyA: "left", ArrowLeft: "left",
  KeyD: "right", ArrowRight: "right"
}

const PAD_DEADZONE = 0.25

export class Input {
  constructor({ onInteract, onCompose }) {
    this.held = new Set()
    this.touchAxis = { x: 0, z: 0 }

    window.addEventListener("keydown", e => {
      if (e.target instanceof HTMLInputElement) return
      if (e.code === "Space") {
        e.preventDefault()
        if (!e.repeat) onInteract()
        return
      }
      if (e.code === "KeyM") {
        e.preventDefault()
        if (!e.repeat) onCompose?.()
        return
      }
      const dir = KEYMAP[e.code]
      if (dir) {
        e.preventDefault()
        this.held.add(dir)
      }
    })

    window.addEventListener("keyup", e => {
      const dir = KEYMAP[e.code]
      if (dir) this.held.delete(dir)
    })

    window.addEventListener("blur", () => this.held.clear())

    this.#setupTouch(onInteract, onCompose)
  }

  // Screen-space intent: x = right(+)/left(-), z = down(+)/up(-).
  // Keyboard wins when held; otherwise the (analog) touch pad.
  get axis() {
    const x = (this.held.has("right") ? 1 : 0) - (this.held.has("left") ? 1 : 0)
    const z = (this.held.has("down") ? 1 : 0) - (this.held.has("up") ? 1 : 0)
    if (x || z) return { x, z }
    return this.touchAxis
  }

  #setupTouch(onInteract, onCompose) {
    const controls = document.getElementById("touch-controls")
    if (!controls) return

    const enable = () => {
      controls.classList.remove("hidden")
      document.getElementById("game")?.classList.add("touch-enabled")
    }

    // Coarse primary pointer = phone/tablet. Hybrids (touch laptops) get the
    // controls the moment the screen is first touched. ?touch=1 forces them
    // on for testing.
    if (matchMedia("(pointer: coarse)").matches) enable()
    else window.addEventListener("touchstart", enable, { once: true })
    if (new URLSearchParams(location.search).has("touch")) enable()

    const pad = document.getElementById("touch-pad")
    const nub = document.getElementById("touch-nub")
    let padPointer = null

    const track = e => {
      const rect = pad.getBoundingClientRect()
      const r = rect.width / 2
      let dx = (e.clientX - (rect.left + r)) / r
      let dy = (e.clientY - (rect.top + r)) / r
      const m = Math.hypot(dx, dy)
      if (m > 1) { dx /= m; dy /= m }
      nub.style.transform = `translate(${dx * r * 0.55}px, ${dy * r * 0.55}px)`
      this.touchAxis = m < PAD_DEADZONE ? { x: 0, z: 0 } : { x: dx, z: dy }
    }

    const release = e => {
      if (e.pointerId !== padPointer) return
      padPointer = null
      this.touchAxis = { x: 0, z: 0 }
      nub.style.transform = ""
    }

    pad.addEventListener("pointerdown", e => {
      e.preventDefault()
      padPointer = e.pointerId
      pad.setPointerCapture(e.pointerId)
      track(e)
    })
    pad.addEventListener("pointermove", e => {
      if (e.pointerId === padPointer) track(e)
    })
    pad.addEventListener("pointerup", release)
    pad.addEventListener("pointercancel", release)

    document.getElementById("touch-action").addEventListener("pointerdown", e => {
      e.preventDefault()
      onInteract()
    })

    document.getElementById("touch-message")?.addEventListener("pointerdown", e => {
      e.preventDefault()
      onCompose?.()
    })
  }
}
