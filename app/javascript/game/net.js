import { createConsumer } from "@rails/actioncable"

// Thin wrapper over the ActionCable RoomChannel subscription. The server
// decides which room we are in; re-joining after a room_change picks up the
// player's new room automatically.
export class Net {
  constructor() {
    this.consumer = createConsumer()
    this.sub = null
  }

  join(handlers) {
    this.sub = this.consumer.subscriptions.create("RoomChannel", {
      received: data => handlers[data.type]?.(data),
      connected: () => handlers._connected?.(),
      disconnected: () => handlers._disconnected?.()
    })
  }

  leave() {
    this.sub?.unsubscribe()
    this.sub = null
  }

  move(x, z, heading, moving) {
    this.sub?.perform("move", { x, z, heading, moving })
  }

  interact() {
    this.sub?.perform("interact", {})
  }

  useExit(id) {
    this.sub?.perform("use_exit", { id })
  }

  readBoard(id) {
    this.sub?.perform("read_board", { id })
  }

  postNote(id, text) {
    this.sub?.perform("post_note", { id, text })
  }

  readWall(id) {
    this.sub?.perform("read_wall", { id })
  }

  postDrawing(id, image) {
    this.sub?.perform("post_drawing", { id, image })
  }

  readSoapstones() {
    this.sub?.perform("read_soapstones", {})
  }

  placeSoapstone(glyph, text) {
    this.sub?.perform("place_soapstone", { glyph, text })
  }
}
