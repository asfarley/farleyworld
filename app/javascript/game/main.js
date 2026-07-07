import * as THREE from "three"
import { buildWorld, prerenderBackground, setCanvasImage } from "game/world"
import { Character } from "game/character"
import { Net } from "game/net"
import { Input } from "game/input"
import { ui } from "game/ui"

const RENDER_SCALE = 1 / 3 // internal resolution vs CSS pixels — the PS1 look
const DESIGN_ASPECT = 1.35 // landscape aspect the fixed cameras are framed for
const WALK_SPEED = 4.0     // units / second
const SEND_INTERVAL = 0.1  // seconds between network position updates
const INTERACT_RANGE = 1.6
const PROMPT_VERB = { noteboard: "read", graffiti: "paint" } // SPACE hint by interactable kind

export function boot() {
  const root = document.getElementById("game")
  const me = { id: Number(root.dataset.playerId), name: root.dataset.playerName }
  const canvas = document.getElementById("game-canvas")

  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false })
  renderer.autoClear = false

  const net = new Net()
  const remotes = new Map() // player id -> { char, tx, tz, theading }

  const preview = new URLSearchParams(location.search).has("preview")
  let world = null       // { room, walkmesh, envScene, actorScene, camera }
  let background = null  // { scene, camera, dispose }
  let basis = null       // camera-aligned ground vectors for input mapping
  let local = null       // { char, x, z, heading, moving }
  let exiting = false
  let openBoardId = null // id of the noteboard whose panel is currently open
  let openWallId = null  // id of the graffiti wall whose editor is currently open
  const wallImages = new Map() // wall id -> latest PNG data URL, for editor preload
  let sendTimer = 0
  let lastSent = { x: null, z: null, heading: null, moving: false }

  async function loadRoom(slug) {
    if (!preview) ui.fade(true)
    ui.prompt(null)
    ui.closeDialog()
    ui.closeBoard()
    ui.closeGraffiti()
    openBoardId = null
    openWallId = null
    wallImages.clear()

    const room = await fetch(`/rooms/${slug}`).then(r => r.json())

    for (const remote of remotes.values()) remote.char.dispose()
    remotes.clear()
    local = null
    background?.dispose()

    world = buildWorld(room)
    refreshViewport()
    ui.setRoom(room.name)
    ui.setOnline(1)
    exiting = false
    setTimeout(() => ui.fade(false), 120)
  }

  function refreshViewport() {
    // Keep the internal short edge ≳220px so phones don't become pure mush;
    // desktops stay at the fixed retro scale.
    const short = Math.min(root.clientWidth, root.clientHeight)
    const scale = Math.min(1, Math.max(RENDER_SCALE, 220 / short))
    const w = Math.max(2, Math.floor(root.clientWidth * scale))
    const h = Math.max(2, Math.floor(root.clientHeight * scale))
    renderer.setSize(w, h, false)
    if (!world) return
    world.camera.aspect = w / h

    // The rooms are framed for a landscape viewport. Because a PerspectiveCamera
    // holds its *vertical* FOV constant, a narrow portrait phone shrinks the
    // *horizontal* FOV and crops the room's sides/corners. Dolly the camera
    // straight back (no FOV change → no perspective distortion) so the whole
    // room stays in frame; landscape/desktop viewports (aspect ≥ DESIGN_ASPECT)
    // are left untouched.
    const cam = world.room.camera
    const look = new THREE.Vector3(...cam.look_at)
    const eye = new THREE.Vector3(...cam.position)
    const dolly = Math.max(1, DESIGN_ASPECT / world.camera.aspect)
    world.camera.position.copy(look).addScaledVector(eye.sub(look), dolly)
    world.camera.lookAt(look)
    world.camera.updateProjectionMatrix()

    background?.dispose()
    background = prerenderBackground(renderer, world, w, h)

    // Ground-projected camera vectors so "up" on the keyboard means
    // "away from the camera" in the world.
    const forward = new THREE.Vector3()
    world.camera.getWorldDirection(forward)
    forward.y = 0
    forward.normalize()
    const right = new THREE.Vector3().crossVectors(forward, new THREE.Vector3(0, 1, 0))
    basis = { forward, right }
  }

  function spawnLocal(state) {
    local?.char.dispose()
    const char = new Character(me.name)
    world.actorScene.add(char.group)
    local = { char, x: state.x, z: state.z, heading: state.heading, moving: false }
    placeCharacter(char, state.x, state.z, state.heading)
  }

  function addRemote(state) {
    if (state.id === me.id || remotes.has(state.id) || !world) return
    const char = new Character(state.name)
    world.actorScene.add(char.group)
    remotes.set(state.id, { char, tx: state.x, tz: state.z, theading: state.heading })
    placeCharacter(char, state.x, state.z, state.heading)
    ui.setOnline(remotes.size + 1)
  }

  function removeRemote(id) {
    const remote = remotes.get(id)
    if (!remote) return
    ui.notice(`${remote.char.name} left.`)
    remote.char.dispose()
    remotes.delete(id)
    ui.setOnline(remotes.size + 1)
  }

  function placeCharacter(char, x, z, heading) {
    const y = world.walkmesh.heightAt(x, z) ?? 0
    char.setPosition(x, y, z)
    char.setHeading(heading)
  }

  const handlers = {
    roster(data) {
      // Arrives on every (re)subscribe — rebuild the whole cast so a cable
      // reconnect can't duplicate characters or leave ghosts behind.
      for (const remote of remotes.values()) remote.char.dispose()
      remotes.clear()
      spawnLocal(data.you)
      for (const p of data.players) addRemote(p)
      ui.setOnline(remotes.size + 1)
      // Pull each graffiti wall's current mural now the subscription is live.
      if (!preview) {
        for (const item of world.room.interactables || []) {
          if (item.kind === "graffiti") net.readWall(item.id)
        }
      }
    },
    player_joined(data) {
      if (data.player.id === me.id) return
      addRemote(data.player)
      ui.notice(`${data.player.name} entered.`)
    },
    player_left(data) {
      removeRemote(data.id)
    },
    player_moved(data) {
      if (data.id === me.id) return
      const remote = remotes.get(data.id)
      if (!remote) return
      remote.tx = data.x
      remote.tz = data.z
      remote.theading = data.heading
      remote.char.moving = !!data.moving
    },
    interaction(data) {
      if (data.actor_id === me.id) {
        ui.dialog(data.target, data.text)
      } else {
        ui.notice(data.text)
      }
    },
    board_notes(data) {
      if (ui.boardOpen && data.board === openBoardId) ui.renderNotes(data.notes)
    },
    note_posted(data) {
      if (ui.boardOpen && data.board === openBoardId) ui.prependNote(data.note)
      if (data.actor_id !== me.id) ui.notice(`${data.actor_name} pinned a note.`)
    },
    wall_image(data) {
      if (data.image) wallImages.set(data.wall, data.image)
      else wallImages.delete(data.wall)
      if (world) setCanvasImage(world, data.wall, data.image)
    },
    wall_drawn(data) {
      wallImages.set(data.wall, data.image)
      if (world) setCanvasImage(world, data.wall, data.image)
      if (data.actor_id !== me.id) ui.notice(`${data.actor_name} tagged the wall.`)
    },
    async room_change(data) {
      net.leave()
      await loadRoom(data.slug)
      net.join(handlers)
    }
  }

  function openBoard(item) {
    openBoardId = item.id
    ui.openBoard(item.name, item.text)
    if (preview) {
      const now = Math.floor(Date.now() / 1000)
      ui.renderNotes([
        { id: -1, author: "Tifa", body: "Meet at the fountain at midnight.", at: now - 600 },
        { id: -2, author: "Barret", body: "Who keeps unplugging the jukebox??", at: now - 90000 }
      ])
    } else {
      net.readBoard(item.id)
    }
  }

  ui.onPostNote = text => {
    if (openBoardId) net.postNote(openBoardId, text)
  }

  function openGraffiti(item) {
    openWallId = item.id
    ui.openGraffiti(item.name, item.text, wallImages.get(item.id))
  }

  ui.onSubmitGraffiti = image => {
    if (!openWallId) return
    if (preview) setCanvasImage(world, openWallId, image) // no server offline — paint locally
    else net.postDrawing(openWallId, image)
    openWallId = null
  }

  const input = new Input({
    onInteract() {
      if (ui.boardOpen || ui.graffitiOpen) return
      if (ui.dialogOpen) {
        ui.closeDialog()
      } else if (!exiting) {
        const item = nearestInteractable()
        if (item?.kind === "noteboard") openBoard(item)
        else if (item?.kind === "graffiti") openGraffiti(item)
        else net.interact()
      }
    }
  })

  function nearestInteractable() {
    if (!world || !local) return null
    let best = null
    let bestDist = Infinity
    for (const item of world.room.interactables || []) {
      const d = Math.hypot(item.x - local.x, item.z - local.z)
      if (d <= (item.radius ?? 1.5) && d < bestDist) {
        best = item
        bestDist = d
      }
    }
    return best
  }

  function nearestRemote() {
    if (!local) return null
    let best = null
    let bestDist = Infinity
    for (const remote of remotes.values()) {
      const d = Math.hypot(remote.tx - local.x, remote.tz - local.z)
      if (d <= INTERACT_RANGE && d < bestDist) {
        best = remote
        bestDist = d
      }
    }
    return best
  }

  function stepLocal(dt) {
    const axis = input.axis
    const wantsMove = (axis.x !== 0 || axis.z !== 0) && !ui.dialogOpen && !ui.boardOpen && !ui.graffitiOpen && !exiting

    if (wantsMove) {
      const dir = new THREE.Vector3()
        .addScaledVector(basis.right, axis.x)
        .addScaledVector(basis.forward, -axis.z)
        .normalize()
      const [nx, nz] = world.walkmesh.resolveMove(
        local.x, local.z,
        local.x + dir.x * WALK_SPEED * dt,
        local.z + dir.z * WALK_SPEED * dt
      )
      local.moving = nx !== local.x || nz !== local.z
      if (local.moving) {
        local.x = nx
        local.z = nz
        local.heading = Math.atan2(dir.x, dir.z)
      }
    } else {
      local.moving = false
    }

    local.char.moving = local.moving
    placeCharacter(local.char, local.x, local.z, local.heading)

    // Throttled state sync; always flush the transition to "stopped".
    sendTimer += dt
    const dirty = local.x !== lastSent.x || local.z !== lastSent.z ||
                  local.heading !== lastSent.heading || local.moving !== lastSent.moving
    if (dirty && (sendTimer >= SEND_INTERVAL || (!local.moving && lastSent.moving))) {
      net.move(local.x, local.z, local.heading, local.moving)
      lastSent = { x: local.x, z: local.z, heading: local.heading, moving: local.moving }
      sendTimer = 0
    }

    // Walking into an exit zone starts a room transition.
    if (!exiting) {
      for (const exit of world.room.exits || []) {
        if (Math.hypot(exit.x - local.x, exit.z - local.z) <= (exit.radius ?? 1.0)) {
          exiting = true
          ui.fade(true)
          net.useExit(exit.id)
          break
        }
      }
    }

    if (ui.dialogOpen || ui.boardOpen || ui.graffitiOpen || exiting) {
      ui.prompt(null)
    } else {
      const item = nearestInteractable()
      const other = item ? null : nearestRemote()
      if (item) ui.prompt(`SPACE — ${PROMPT_VERB[item.kind] || "check"} ${item.name}`)
      else if (other) ui.prompt(`SPACE — greet ${other.char.name}`)
      else ui.prompt(null)
    }
  }

  function stepRemotes(dt) {
    const k = 1 - Math.exp(-10 * dt)
    for (const remote of remotes.values()) {
      const pos = remote.char.group.position
      const x = pos.x + (remote.tx - pos.x) * k
      const z = pos.z + (remote.tz - pos.z) * k
      const heading = lerpAngle(remote.char.group.rotation.y, remote.theading, k)
      placeCharacter(remote.char, x, z, heading)
      if (Math.hypot(remote.tx - x, remote.tz - z) < 0.02) remote.char.moving = false
    }
  }

  let lastTime = performance.now()
  function frame(now) {
    const dt = Math.min(0.05, (now - lastTime) / 1000)
    lastTime = now

    if (world && background) {
      if (local) stepLocal(dt)
      stepRemotes(dt)
      if (local) local.char.update(dt)
      for (const remote of remotes.values()) remote.char.update(dt)

      renderer.clear()
      renderer.render(background.scene, background.camera)
      renderer.render(world.actorScene, world.camera)
    }
    requestAnimationFrame(frame)
  }

  let resizeTimer = null
  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer)
    resizeTimer = setTimeout(refreshViewport, 150)
  })

  // ?preview=1 skips networking and stages fake players — for eyeballing
  // rendering, characters and occlusion without a second client.
  function startPreview() {
    const spawn = world.room.spawn
    handlers.roster({ you: { id: me.id, name: me.name, ...spawn }, players: [] })
    handlers.player_joined({ player: { id: -1, name: "Tifa", x: -2, z: 1, heading: 1 } })
    handlers.player_joined({ player: { id: -2, name: "Barret", x: 3.5, z: -1, heading: -0.6 } })
    // Stage a demo mural on any graffiti wall so ?preview shows the feature.
    for (const item of world.room.interactables || []) {
      if (item.kind === "graffiti") setCanvasImage(world, item.id, demoMural())
    }
    let t = 0
    setInterval(() => {
      t += 0.12
      handlers.player_moved({
        id: -1,
        x: -2 + Math.cos(t) * 1.2, z: 1 + Math.sin(t) * 1.2,
        heading: t + Math.PI / 2, moving: true
      })
    }, 120)
  }

  function demoMural() {
    const c = document.createElement("canvas")
    c.width = 512; c.height = 320
    const g = c.getContext("2d")
    g.lineCap = "round"; g.lineJoin = "round"
    g.strokeStyle = "#f4e04d"; g.lineWidth = 16
    g.beginPath(); g.moveTo(60, 250); g.quadraticCurveTo(150, 60, 250, 200)
    g.quadraticCurveTo(340, 320, 440, 90); g.stroke()
    g.strokeStyle = "#31c4d4"; g.lineWidth = 10
    g.beginPath(); g.arc(370, 210, 60, 0, Math.PI * 2); g.stroke()
    g.fillStyle = "#ff6fb5"
    g.beginPath(); g.arc(150, 150, 26, 0, Math.PI * 2); g.fill()
    return c.toDataURL("image/png")
  }

  loadRoom(root.dataset.roomSlug).then(() => {
    if (preview) startPreview()
    else net.join(handlers)
    requestAnimationFrame(frame)
  }).catch(e => {
    console.error("failed to load room:", e)
    window.dbg?.("loadRoom failed: " + e)
  })
}

function lerpAngle(a, b, k) {
  let d = (b - a) % (Math.PI * 2)
  if (d > Math.PI) d -= Math.PI * 2
  if (d < -Math.PI) d += Math.PI * 2
  return a + d * k
}
