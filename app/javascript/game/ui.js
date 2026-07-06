// DOM chrome: room name, online count, interaction prompt, FF-style dialog
// box, transient notices and the room-transition fade.
const el = id => document.getElementById(id)

let dialogTimer = null

// On touch screens the dialog itself is the most natural dismiss target.
el("dialog")?.addEventListener("pointerdown", () => ui.closeDialog())

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
