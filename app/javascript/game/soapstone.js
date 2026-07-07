import * as THREE from "three"

// The glyphs a soapstone may show; also the palette in the composer. This must
// match Soapstone::GLYPHS on the server (it validates against the same set).
export const SOAPSTONE_GLYPHS = ["✦", "➤", "◆", "✕", "✚", "☉", "♥", "✷"]

// A Dark Souls-style ground message: a glowing orange sigil laid flat on the
// floor at the writer's position. The message text isn't shown until a player
// walks up and examines it (SPACE) — see main.js — matching the "read the
// message" feel. Lives in the actor scene so foreground scenery still occludes
// it via the pre-rendered depth buffer.
export class Soapstone {
  constructor(data) {
    this.data = data
    this.phase = Math.random() * Math.PI * 2 // desync the glow pulses

    const texture = glyphTexture(data.glyph)
    this.material = new THREE.MeshBasicMaterial({
      map: texture,
      transparent: true,
      depthWrite: false,               // a floor decal — never occludes characters
      blending: THREE.AdditiveBlending // orange glow that reads over any floor
    })
    this.mesh = new THREE.Mesh(new THREE.PlaneGeometry(1.4, 1.4), this.material)
    // Spin around the vertical axis by the writer's heading, then lay flat.
    this.mesh.rotation.order = "YXZ"
    this.mesh.rotation.set(-Math.PI / 2, data.heading || 0, 0)
    this.mesh.renderOrder = -1         // draw beneath the characters
  }

  // Sit the sigil just above the floor so it paints over it without z-fighting.
  place(y) {
    this.mesh.position.set(this.data.x, y + 0.04, this.data.z)
  }

  update(dt) {
    this.phase += dt * 2.2
    this.material.opacity = 0.6 + Math.sin(this.phase) * 0.22
  }

  dispose() {
    this.material.map.dispose()
    this.material.dispose()
    this.mesh.geometry.dispose()
    this.mesh.removeFromParent()
  }
}

// Rasterize one glyph as a soft orange glow with the sigil stamped in the
// middle — the soapstone "summon sign" look.
function glyphTexture(glyph) {
  const canvas = document.createElement("canvas")
  canvas.width = canvas.height = 128
  const ctx = canvas.getContext("2d")
  const c = 64

  const glow = ctx.createRadialGradient(c, c, 3, c, c, c)
  glow.addColorStop(0, "#ffe6b0")
  glow.addColorStop(0.4, "#ff9d3a99")
  glow.addColorStop(1, "#ff8a0000")
  ctx.fillStyle = glow
  ctx.beginPath()
  ctx.arc(c, c, c, 0, Math.PI * 2)
  ctx.fill()

  // The U+FE0E variation selector asks for the flat (non-emoji) rendering so
  // glyphs stay monochrome orange rather than turning into color emoji.
  ctx.font = "bold 68px serif"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  ctx.shadowColor = "#ff9020"
  ctx.shadowBlur = 12
  ctx.fillStyle = "#fff2d6"
  ctx.fillText(glyph + "\uFE0E", c, c + 4)

  const texture = new THREE.CanvasTexture(canvas)
  texture.minFilter = THREE.LinearFilter
  return texture
}
