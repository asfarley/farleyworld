# Synchronizes world state for the room the current player occupies.
# The client reports movement intents; the server validates them against
# the room's walkmesh before persisting and rebroadcasting.
class RoomChannel < ApplicationCable::Channel
  # Max distance a player may cover between two move messages (~10Hz at
  # 4 units/sec is 0.4; generous slack for lag spikes).
  MAX_STEP = 3.0
  INTERACT_RANGE = 1.8

  def subscribed
    @room = current_player.room
    stream_for @room

    current_player.update_columns(last_seen_at: Time.current)
    others = @room.players.active.where.not(id: current_player.id).map(&:as_state)
    transmit({ "type" => "roster", "you" => current_player.as_state, "players" => others })
    broadcast({ "type" => "player_joined", "player" => current_player.as_state })
  end

  def unsubscribed
    broadcast({ "type" => "player_left", "id" => current_player.id }) if @room
  end

  def move(data)
    x, z, heading = data["x"].to_f, data["z"].to_f, data["heading"].to_f
    return unless @room.contains?(x, z)
    return if Math.hypot(x - current_player.x, z - current_player.z) > MAX_STEP

    current_player.update_columns(x: x, z: z, heading: heading, last_seen_at: Time.current)
    broadcast({
      "type" => "player_moved", "id" => current_player.id,
      "x" => x, "z" => z, "heading" => heading, "moving" => !!data["moving"]
    })
  end

  def interact(_data = {})
    me = current_player.reload

    if (target = @room.nearest_interactable(me.x, me.z))
      broadcast({
        "type" => "interaction", "actor_id" => me.id, "actor_name" => me.name,
        "target" => target["name"], "text" => target["text"]
      })
    elsif (other = nearby_player(me))
      broadcast({
        "type" => "interaction", "actor_id" => me.id, "actor_name" => me.name,
        "target" => other.name, "text" => "#{me.name} waves at #{other.name}."
      })
    else
      transmit({ "type" => "interaction", "actor_id" => me.id, "actor_name" => me.name,
                 "target" => nil, "text" => "There is nothing here." })
    end
  end

  # Note boards. read_board answers the requester only; post_note validates
  # proximity (like interact) then broadcasts so every open board updates live.
  def read_board(data)
    board = board_near(current_player.reload, data["id"].to_s)
    return unless board

    notes = Note.for_board(@room, board["id"]).recent.limit(Note::KEEP).map(&:to_payload)
    transmit({ "type" => "board_notes", "board" => board["id"], "notes" => notes })
  end

  def post_note(data)
    me = current_player.reload
    board = board_near(me, data["id"].to_s)
    return unless board

    body = data["text"].to_s.strip[0, Note::MAX_BODY].to_s
    return if body.empty?

    note = Note.create!(room: @room, board_id: board["id"], author: me.name, body: body)
    broadcast({
      "type" => "note_posted", "board" => board["id"], "note" => note.to_payload,
      "actor_id" => me.id, "actor_name" => me.name
    })
  end

  # Graffiti walls. read_wall is public room state (the mural is drawn for
  # everyone in the room, wherever they stand); post_drawing validates
  # proximity like post_note, then broadcasts so every wall repaints live.
  def read_wall(data)
    wall = @room.interactables.find { |i| i["id"] == data["id"].to_s && i["kind"] == "graffiti" }
    return unless wall

    drawing = Drawing.for_wall(@room, wall["id"]).recent.first
    transmit({ "type" => "wall_image", "wall" => wall["id"], "image" => drawing&.image })
  end

  def post_drawing(data)
    me = current_player.reload
    wall = wall_near(me, data["id"].to_s)
    return unless wall

    image = data["image"].to_s
    return unless Drawing.valid_image?(image)

    drawing = Drawing.create!(room: @room, wall_id: wall["id"], author: me.name, image: image)
    Drawing.prune(@room, wall["id"])
    broadcast({
      "type" => "wall_drawn", "wall" => wall["id"], "image" => drawing.image,
      "actor_id" => me.id, "actor_name" => me.name
    })
  end

  # Soapstone messages. read_soapstones is public room state (every message is
  # drawn on the floor for everyone, wherever they stand); place_soapstone drops
  # one at the writer's own feet, so it only has to sit on the walkmesh.
  def read_soapstones(_data = {})
    list = Soapstone.for_room(@room).recent.limit(Soapstone::KEEP).map(&:to_payload)
    transmit({ "type" => "soapstones", "list" => list })
  end

  def place_soapstone(data)
    me = current_player.reload
    return unless @room.contains?(me.x, me.z)

    glyph = data["glyph"].to_s
    return unless Soapstone::GLYPHS.include?(glyph)
    body = data["text"].to_s.strip[0, Soapstone::MAX_BODY].to_s
    return if body.empty?

    stone = Soapstone.create!(room: @room, x: me.x, z: me.z, heading: me.heading,
                              glyph: glyph, body: body, author: me.name)
    Soapstone.prune(@room)
    broadcast({
      "type" => "soapstone_placed", "soapstone" => stone.to_payload,
      "actor_id" => me.id, "actor_name" => me.name
    })
  end

  def use_exit(data)
    me = current_player.reload
    exit_def = @room.exit_near(me.x, me.z, data["id"].to_s)
    return unless exit_def

    dest = Room.find_by(slug: exit_def["to"])
    return unless dest

    old_room = @room
    @room = nil # unsubscribed callback must not announce departure twice
    spawn = exit_def["spawn"]
    me.update!(room: dest, x: spawn["x"], z: spawn["z"], heading: spawn.fetch("heading", 0.0),
               last_seen_at: Time.current)

    self.class.broadcast_to(old_room, { "type" => "player_left", "id" => me.id })
    transmit({ "type" => "room_change", "slug" => dest.slug })
  end

  private

  def broadcast(payload)
    self.class.broadcast_to(@room, payload)
  end

  # The noteboard interactable with the given id, if the player is close
  # enough to it to read or post. Generous slack — movement is locked while a
  # board is open, so the player is already within radius.
  def board_near(me, id)
    board = @room.interactables.find { |i| i["id"] == id && i["kind"] == "noteboard" }
    return unless board
    return unless Math.hypot(board["x"] - me.x, board["z"] - me.z) <= board.fetch("radius", 1.5) + INTERACT_RANGE

    board
  end

  # The graffiti interactable with the given id, if the player is close enough
  # to spray it. Same generous slack as board_near — movement is locked while
  # the editor is open, so the player is already within radius.
  def wall_near(me, id)
    wall = @room.interactables.find { |i| i["id"] == id && i["kind"] == "graffiti" }
    return unless wall
    return unless Math.hypot(wall["x"] - me.x, wall["z"] - me.z) <= wall.fetch("radius", 1.5) + INTERACT_RANGE

    wall
  end

  def nearby_player(me)
    @room.players.active.where.not(id: me.id)
         .min_by { |p| Math.hypot(p.x - me.x, p.z - me.z) }
         &.then { |p| Math.hypot(p.x - me.x, p.z - me.z) <= INTERACT_RANGE ? p : nil }
  end
end
