import * as THREE from "three"
import { buildWorld, prerenderBackground } from "game/world"
import { Character } from "game/character"
import { Net } from "game/net"
import { Input } from "game/input"
import { ui } from "game/ui"

const RENDER_SCALE = 1 / 3 // internal resolution vs CSS pixels — the PS1 look
const WALK_SPEED = 4.0     // units / second
const SEND_INTERVAL = 0.1  // seconds between network position updates
const INTERACT_RANGE = 1.6

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
  let sendTimer = 0
  let lastSent = { x: null, z: null, heading: null, moving: false }

  async function loadRoom(slug) {
    if (!preview) ui.fade(true)
    ui.prompt(null)
    ui.closeDialog()

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
    const w = Math.max(2, Math.floor(root.clientWidth * RENDER_SCALE))
    const h = Math.max(2, Math.floor(root.clientHeight * RENDER_SCALE))
    renderer.setSize(w, h, false)
    if (!world) return
    world.camera.aspect = w / h
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
    async room_change(data) {
      net.leave()
      await loadRoom(data.slug)
      net.join(handlers)
    }
  }

  const input = new Input({
    onInteract() {
      if (ui.dialogOpen) {
        ui.closeDialog()
      } else if (!exiting) {
        net.interact()
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
    const wantsMove = (axis.x !== 0 || axis.z !== 0) && !ui.dialogOpen && !exiting

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

    if (ui.dialogOpen || exiting) {
      ui.prompt(null)
    } else {
      const item = nearestInteractable()
      const other = item ? null : nearestRemote()
      if (item) ui.prompt(`SPACE — check ${item.name}`)
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
