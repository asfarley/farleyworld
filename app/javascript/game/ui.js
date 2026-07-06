// DOM chrome: room name, online count, interaction prompt, FF-style dialog
// box, the note board, transient notices and the room-transition fade.
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
