const KEYMAP = {
  KeyW: "up", ArrowUp: "up",
  KeyS: "down", ArrowDown: "down",
  KeyA: "left", ArrowLeft: "left",
  KeyD: "right", ArrowRight: "right"
}

export class Input {
  constructor({ onInteract }) {
    this.held = new Set()

    window.addEventListener("keydown", e => {
      if (e.target instanceof HTMLInputElement) return
      if (e.code === "Space") {
        e.preventDefault()
        if (!e.repeat) onInteract()
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
  }

  // Screen-space intent: x = right(+)/left(-), z = down(+)/up(-)
  get axis() {
    return {
      x: (this.held.has("right") ? 1 : 0) - (this.held.has("left") ? 1 : 0),
      z: (this.held.has("down") ? 1 : 0) - (this.held.has("up") ? 1 : 0)
    }
  }
}
