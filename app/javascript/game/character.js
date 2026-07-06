import * as THREE from "three"

// Chunky low-poly PS1-style avatar assembled from boxes, with a procedural
// walk cycle and a floating name label.
export class Character {
  constructor(name) {
    this.name = name
    this.moving = false
    this.phase = 0

    const hue = nameHash(name) % 360
    const shirt = new THREE.MeshLambertMaterial({ color: hsl(hue, 55, 52) })
    const pants = new THREE.MeshLambertMaterial({ color: hsl(hue, 40, 30) })
    const skin = new THREE.MeshLambertMaterial({ color: "#e8b890" })
    const hair = new THREE.MeshLambertMaterial({ color: hsl((hue + 140) % 360, 45, 32) })

    this.group = new THREE.Group()

    this.body = new THREE.Mesh(new THREE.BoxGeometry(0.55, 0.6, 0.32), shirt)
    this.body.position.y = 0.85
    this.group.add(this.body)

    const head = new THREE.Mesh(new THREE.BoxGeometry(0.38, 0.36, 0.36), skin)
    head.position.y = 0.5
    this.body.add(head)

    const cap = new THREE.Mesh(new THREE.BoxGeometry(0.42, 0.14, 0.4), hair)
    cap.position.y = 0.71
    this.body.add(cap)

    this.limbs = {}
    for (const [key, w, h, mat, px, py] of [
      ["armL", 0.16, 0.55, shirt, -0.36, 1.15],
      ["armR", 0.16, 0.55, shirt, 0.36, 1.15],
      ["legL", 0.2, 0.58, pants, -0.14, 0.58],
      ["legR", 0.2, 0.58, pants, 0.14, 0.58]
    ]) {
      const geo = new THREE.BoxGeometry(w, h, w)
      geo.translate(0, -h / 2, 0) // pivot at the top so limbs swing from the joint
      const limb = new THREE.Mesh(geo, mat)
      limb.position.set(px, py, 0)
      this.limbs[key] = limb
      this.group.add(limb)
    }

    this.label = makeLabel(name)
    this.label.position.y = 2.0
    this.group.add(this.label)
  }

  setPosition(x, y, z) {
    this.group.position.set(x, y, z)
  }

  setHeading(heading) {
    this.group.rotation.y = heading
  }

  update(dt) {
    if (this.moving) {
      this.phase += dt * 9
      const swing = Math.sin(this.phase) * 0.75
      this.limbs.legL.rotation.x = swing
      this.limbs.legR.rotation.x = -swing
      this.limbs.armL.rotation.x = -swing * 0.8
      this.limbs.armR.rotation.x = swing * 0.8
      this.body.position.y = 0.85 + Math.abs(Math.cos(this.phase)) * 0.045
    } else {
      for (const limb of Object.values(this.limbs)) limb.rotation.x *= Math.max(0, 1 - dt * 12)
      this.body.position.y += (0.85 - this.body.position.y) * Math.min(1, dt * 12)
    }
  }

  dispose() {
    this.label.material.map.dispose()
    this.label.material.dispose()
    this.group.removeFromParent()
  }
}

function makeLabel(name) {
  const canvas = document.createElement("canvas")
  canvas.width = 256
  canvas.height = 64
  const ctx = canvas.getContext("2d")
  ctx.font = "bold 30px monospace"
  ctx.textAlign = "center"
  ctx.textBaseline = "middle"
  ctx.lineWidth = 6
  ctx.strokeStyle = "#000000"
  ctx.strokeText(name, 128, 32)
  ctx.fillStyle = "#ffffff"
  ctx.fillText(name, 128, 32)

  const texture = new THREE.CanvasTexture(canvas)
  texture.minFilter = THREE.LinearFilter
  const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: texture, transparent: true }))
  sprite.scale.set(1.7, 0.42, 1)
  return sprite
}

function nameHash(name) {
  let h = 0
  for (let i = 0; i < name.length; i++) h = (h * 31 + name.charCodeAt(i)) >>> 0
  return h
}

function hsl(h, s, l) {
  return new THREE.Color(`hsl(${h}, ${s}%, ${l}%)`)
}
