// DOM chrome: room name, online count, interaction prompt, FF-style dialog
// box, the note board, the soapstone composer, transient notices and the
// room-transition fade.
import { SOAPSTONE_GLYPHS } from "game/soapstone"

const el = id => document.getElementById(id)

let dialogTimer = null

// On touch screens the dialog itself is the most natural dismiss target.
el("dialog")?.addEventListener("pointerdown", () => ui.closeDialog())

// ---- Note board wiring ----
el("noteboard-close")?.addEventListener("click", () => ui.closeBoard())
el("noteboard-form")?.addEventListener("submit", e => {
  e.preventDefault()
  const input = el("noteboard-input")
  const text = input.value.trim()
  if (!text) return
  ui.onPostNote?.(text)
  input.value = ""
})
window.addEventListener("keydown", e => {
  if (e.key === "Escape" && ui.boardOpen) ui.closeBoard()
})

// ---- Graffiti wall editor ----
// A pop-up canvas the player draws on; the export is a transparent PNG that
// gets sprayed onto the wall. The concrete backdrop is CSS only — never part
// of the exported pixels — so unpainted areas stay see-through.
const GRAFFITI_COLORS = ["#ffffff", "#111111", "#e8443b", "#f6a623",
                         "#f4e04d", "#3fb950", "#31c4d4", "#3b7bf6",
                         "#b45cf0", "#ff6fb5"]
const GRAFFITI_SIZES = [{ label: "S", px: 4 }, { label: "M", px: 11 }, { label: "L", px: 24 }]

const gcanvas = el("graffiti-canvas")
const gctx = gcanvas?.getContext("2d")
let gColor = GRAFFITI_COLORS[4]
let gSize = GRAFFITI_SIZES[1].px
let gErase = false
let gDrawing = false
let gLast = null

function gGenTools() {
  const colors = el("graffiti-colors")
  GRAFFITI_COLORS.forEach((c, i) => {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "g-swatch"
    b.style.background = c
    b.addEventListener("click", () => { gColor = c; gErase = false; gMark() })
    colors.appendChild(b)
    if (i === 4) b.classList.add("active")
  })
  const eraser = document.createElement("button")
  eraser.type = "button"
  eraser.className = "g-swatch g-eraser"
  eraser.title = "Eraser"
  eraser.textContent = "⌫"
  eraser.addEventListener("click", () => { gErase = true; gMark() })
  colors.appendChild(eraser)

  const sizes = el("graffiti-sizes")
  GRAFFITI_SIZES.forEach(s => {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "g-size"
    b.textContent = s.label
    if (s.px === gSize) b.classList.add("active")
    b.addEventListener("click", () => { gSize = s.px; gMark() })
    sizes.appendChild(b)
  })
}

// Reflect the current tool selection in the toolbar highlights.
function gMark() {
  const swatches = [...el("graffiti-colors").children]
  swatches.forEach(b => b.classList.remove("active"))
  if (gErase) {
    el("graffiti-colors").querySelector(".g-eraser").classList.add("active")
  } else {
    const i = GRAFFITI_COLORS.indexOf(gColor)
    if (i >= 0) swatches[i].classList.add("active")
  }
  ;[...el("graffiti-sizes").children].forEach(b =>
    b.classList.toggle("active", GRAFFITI_SIZES.find(s => s.label === b.textContent)?.px === gSize))
}

function gPoint(e) {
  const r = gcanvas.getBoundingClientRect()
  return {
    x: (e.clientX - r.left) * (gcanvas.width / r.width),
    y: (e.clientY - r.top) * (gcanvas.height / r.height)
  }
}

function gStroke(from, to) {
  gctx.globalCompositeOperation = gErase ? "destination-out" : "source-over"
  gctx.strokeStyle = gColor
  gctx.fillStyle = gColor
  gctx.lineWidth = gSize
  gctx.lineCap = "round"
  gctx.lineJoin = "round"
  gctx.beginPath()
  gctx.moveTo(from.x, from.y)
  gctx.lineTo(to.x, to.y)
  gctx.stroke()
  // A dot too, so a tap (no movement) still leaves a mark.
  gctx.beginPath()
  gctx.arc(to.x, to.y, gSize / 2, 0, Math.PI * 2)
  gctx.fill()
}

if (gcanvas) {
  gGenTools()
  gcanvas.addEventListener("pointerdown", e => {
    gDrawing = true
    gcanvas.setPointerCapture(e.pointerId)
    gLast = gPoint(e)
    gStroke(gLast, gLast)
  })
  gcanvas.addEventListener("pointermove", e => {
    if (!gDrawing) return
    const p = gPoint(e)
    gStroke(gLast, p)
    gLast = p
  })
  const gEnd = () => { gDrawing = false; gLast = null }
  gcanvas.addEventListener("pointerup", gEnd)
  gcanvas.addEventListener("pointercancel", gEnd)
  gcanvas.addEventListener("pointerleave", gEnd)

  el("graffiti-clear")?.addEventListener("click", () =>
    gctx.clearRect(0, 0, gcanvas.width, gcanvas.height))
  el("graffiti-close")?.addEventListener("click", () => ui.closeGraffiti())
  el("graffiti-cancel")?.addEventListener("click", () => ui.closeGraffiti())
  el("graffiti-submit")?.addEventListener("click", () => {
    ui.onSubmitGraffiti?.(gcanvas.toDataURL("image/png"))
    ui.closeGraffiti()
  })
}
window.addEventListener("keydown", e => {
  if (e.key === "Escape" && ui.graffitiOpen) ui.closeGraffiti()
})

// ---- Soapstone composer ----
// Pick a glowing glyph and type a short cryptic line; it's left on the ground
// where the player stands. The glyph set mirrors Soapstone::GLYPHS server-side.
let selectedGlyph = SOAPSTONE_GLYPHS[0]
const sGlyphs = el("soapstone-glyphs")
if (sGlyphs) {
  SOAPSTONE_GLYPHS.forEach((g, i) => {
    const b = document.createElement("button")
    b.type = "button"
    b.className = "s-glyph"
    b.textContent = g
    if (i === 0) b.classList.add("active")
    b.addEventListener("click", () => {
      selectedGlyph = g
      ;[...sGlyphs.children].forEach(c => c.classList.remove("active"))
      b.classList.add("active")
    })
    sGlyphs.appendChild(b)
  })
}
el("soapstone-close")?.addEventListener("click", () => ui.closeSoapstone())
el("soapstone-form")?.addEventListener("submit", e => {
  e.preventDefault()
  const input = el("soapstone-input")
  const text = input.value.trim()
  if (!text) return
  ui.onPlaceSoapstone?.(selectedGlyph, text)
  input.value = ""
  ui.closeSoapstone()
})
window.addEventListener("keydown", e => {
  if (e.key === "Escape" && ui.soapstoneOpen) ui.closeSoapstone()
})

// Builds a note row entirely with textContent — user text never touches innerHTML.
function noteEl(n) {
  const node = document.createElement("div")
  node.className = "note-item"
  const body = document.createElement("div")
  body.className = "note-body"
  body.textContent = n.body
  const meta = document.createElement("div")
  meta.className = "note-meta"
  meta.textContent = `— ${n.author} · ${relTime(n.at)}`
  node.append(body, meta)
  return node
}

function relTime(atSeconds) {
  const s = Math.max(0, Math.floor(Date.now() / 1000) - atSeconds)
  if (s < 60) return "just now"
  if (s < 3600) return `${Math.floor(s / 60)}m ago`
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`
  return `${Math.floor(s / 86400)}d ago`
}

export const ui = {
  get dialogOpen() {
    return !el("dialog").classList.contains("hidden")
  },

  setRoom(name) {
    el("hud-room").textContent = name
  },

  setOnline(count) {
    el("hud-online").textContent = `◆ ${count} here`
  },

  prompt(text) {
    const node = el("prompt")
    if (text) {
      node.textContent = text
      node.classList.remove("hidden")
    } else {
      node.classList.add("hidden")
    }
  },

  dialog(title, text) {
    el("dialog-title").textContent = title || ""
    el("dialog-text").textContent = text
    el("dialog").classList.remove("hidden")
    clearTimeout(dialogTimer)
    dialogTimer = setTimeout(() => ui.closeDialog(), 6000)
  },

  closeDialog() {
    clearTimeout(dialogTimer)
    el("dialog").classList.add("hidden")
  },

  // ---- Note board ----
  onPostNote: null, // set by main.js; called with the note text on submit

  get boardOpen() {
    const b = el("noteboard")
    return b && !b.classList.contains("hidden")
  },

  openBoard(title, subtitle) {
    el("noteboard-title").textContent = title || "NOTICE BOARD"
    el("noteboard-sub").textContent = subtitle || ""
    el("noteboard-notes").textContent = "Loading…"
    el("noteboard").classList.remove("hidden")
    el("noteboard-input").focus()
  },

  closeBoard() {
    el("noteboard").classList.add("hidden")
    el("noteboard-input").blur()
  },

  renderNotes(notes) {
    const list = el("noteboard-notes")
    list.textContent = ""
    if (!notes.length) {
      const empty = document.createElement("div")
      empty.className = "note-empty"
      empty.textContent = "No notes yet. Be the first to pin one."
      list.appendChild(empty)
      return
    }
    for (const n of notes) list.appendChild(noteEl(n))
  },

  prependNote(note) {
    const list = el("noteboard-notes")
    list.querySelector(".note-empty")?.remove()
    list.insertBefore(noteEl(note), list.firstChild)
  },

  // ---- Graffiti wall ----
  onSubmitGraffiti: null, // set by main.js; called with a PNG data URL

  get graffitiOpen() {
    const g = el("graffiti")
    return g && !g.classList.contains("hidden")
  },

  // Opens the editor, preloading the wall's current mural (a PNG data URL) so
  // each artist adds to the shared drawing rather than starting from scratch.
  openGraffiti(title, subtitle, baseImage) {
    el("graffiti-title").textContent = title || "WALL"
    el("graffiti-sub").textContent = subtitle || ""
    gctx.clearRect(0, 0, gcanvas.width, gcanvas.height)
    if (baseImage) {
      const img = new Image()
      img.onload = () => { if (ui.graffitiOpen) gctx.drawImage(img, 0, 0, gcanvas.width, gcanvas.height) }
      img.src = baseImage
    }
    el("graffiti").classList.remove("hidden")
  },

  closeGraffiti() {
    el("graffiti").classList.add("hidden")
  },

  // ---- Soapstone composer ----
  onPlaceSoapstone: null, // set by main.js; called with (glyph, text) on submit

  get soapstoneOpen() {
    const s = el("soapstone")
    return s && !s.classList.contains("hidden")
  },

  openSoapstone() {
    el("soapstone").classList.remove("hidden")
    el("soapstone-input").focus()
  },

  closeSoapstone() {
    el("soapstone").classList.add("hidden")
    el("soapstone-input").blur()
  },

  notice(text) {
    const node = document.createElement("div")
    node.className = "notice"
    node.textContent = text
    el("notices").appendChild(node)
    setTimeout(() => { node.style.opacity = "0" }, 3500)
    setTimeout(() => node.remove(), 4500)
  },

  fade(active) {
    el("fade").classList.toggle("active", active)
  }
}
