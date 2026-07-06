# Farleyworld rooms.
#
# Each room's `data` JSON fully describes it for both server and client:
#   walkmesh      — triangle ground mesh (server validates moves, client walks on it)
#   props         — primitive shapes the client assembles and pre-renders as background
#   camera        — the fixed "pre-rendered" viewpoint
#   interactables — SPACE targets with flavor text
#   exits         — walk-in zones that move the player to another room

# Builds a rectangular grid walkmesh centered on the origin. `height` shapes
# the ground (ramps, platforms); `blocked` (given a cell center) punches holes
# where furniture stands.
def grid_walkmesh(width:, depth:, cell: 1.0, height: nil, blocked: nil)
  height ||= ->(_x, _z) { 0.0 }
  blocked ||= ->(_x, _z) { false }

  ox = -(width * cell) / 2.0
  oz = -(depth * cell) / 2.0

  vertices = []
  index = {}
  (0..depth).each do |j|
    (0..width).each do |i|
      x = ox + i * cell
      z = oz + j * cell
      index[[i, j]] = vertices.length
      vertices << [x.round(4), height.call(x, z).round(4), z.round(4)]
    end
  end

  triangles = []
  (0...depth).each do |j|
    (0...width).each do |i|
      cx = ox + (i + 0.5) * cell
      cz = oz + (j + 0.5) * cell
      next if blocked.call(cx, cz)

      a = index[[i, j]]
      b = index[[i + 1, j]]
      c = index[[i + 1, j + 1]]
      d = index[[i, j + 1]]
      triangles << [a, c, b] << [a, d, c] # CCW seen from above (+y normals)
    end
  end

  { "vertices" => vertices, "triangles" => triangles }
end

# ---------------------------------------------------------------- The Lounge

lounge_height = lambda do |_x, z|
  if z <= -4.0 then 0.75                          # stage platform along the north wall
  elsif z <= -2.5 then 0.75 * ((-2.5 - z) / 1.5)  # ramp down to the main floor
  else 0.0
  end
end

lounge_blocked = lambda do |cx, cz|
  (cx.between?(4.0, 7.0) && cz.between?(0.0, 4.0)) ||     # bar counter
    (cx < -5.2 && cz.between?(-0.5, 3.5)) ||              # sofa corner
    (Math.hypot(cx - 2.5, cz - 1.5) < 0.7) ||             # east pillar
    (Math.hypot(cx + 2.5, cz - 1.5) < 0.7) ||             # west pillar
    (cx.between?(-4.0, -2.0) && cz < -4.8)                # jukebox on stage
end

wall = "#463a55"
wood = "#5a4636"

lounge_props = [
  # walls
  { "type" => "box", "size" => [16.8, 3.4, 0.4], "pos" => [0, 1.7, -6.2], "color" => wall },
  { "type" => "box", "size" => [0.4, 3.4, 12.8], "pos" => [-8.2, 1.7, 0], "color" => wall },
  { "type" => "box", "size" => [0.4, 3.4, 12.8], "pos" => [8.2, 1.7, 0], "color" => wall },
  { "type" => "box", "size" => [7.2, 3.4, 0.4], "pos" => [-4.6, 1.7, 6.2], "color" => wall },
  { "type" => "box", "size" => [7.2, 3.4, 0.4], "pos" => [4.6, 1.7, 6.2], "color" => wall },
  { "type" => "box", "size" => [2.0, 1.0, 0.4], "pos" => [0, 2.9, 6.2], "color" => wall },
  # rug on the main floor
  { "type" => "plane", "size" => [5.0, 3.2], "pos" => [0, 0.012, 1.2], "color" => "#77283a" },
  # pillars (foreground occluders — walk behind them!)
  { "type" => "cylinder", "r" => 0.5, "h" => 3.4, "pos" => [2.5, 1.7, 1.5], "color" => "#6a5a78", "segments" => 8 },
  { "type" => "cylinder", "r" => 0.5, "h" => 3.4, "pos" => [-2.5, 1.7, 1.5], "color" => "#6a5a78", "segments" => 8 },
  # bar counter + back shelf
  { "type" => "box", "size" => [2.6, 1.1, 4.2], "pos" => [5.5, 0.55, 2.0], "color" => wood },
  { "type" => "box", "size" => [2.4, 0.08, 4.0], "pos" => [5.5, 1.14, 2.0], "color" => "#8a6a4a" },
  { "type" => "box", "size" => [0.5, 2.2, 4.2], "pos" => [7.9, 1.1, 2.0], "color" => wood },
  { "type" => "box", "size" => [0.4, 0.5, 3.6], "pos" => [7.85, 2.0, 2.0], "color" => "#3a2e24" },
  # sofa (west corner)
  { "type" => "box", "size" => [1.5, 0.5, 3.6], "pos" => [-6.6, 0.25, 1.5], "color" => "#8a4a4a" },
  { "type" => "box", "size" => [0.4, 1.1, 3.6], "pos" => [-7.3, 0.55, 1.5], "color" => "#7a3a3a" },
  { "type" => "box", "size" => [1.5, 0.35, 0.5], "pos" => [-6.6, 0.65, -0.3], "color" => "#7a3a3a" },
  { "type" => "box", "size" => [1.5, 0.35, 0.5], "pos" => [-6.6, 0.65, 3.3], "color" => "#7a3a3a" },
  # jukebox on stage
  { "type" => "box", "size" => [1.4, 1.7, 0.9], "pos" => [-3.0, 1.6, -5.5], "color" => "#b03a5a" },
  { "type" => "cylinder", "r" => 0.7, "h" => 0.5, "pos" => [-3.0, 2.45, -5.45], "color" => "#d05a7a", "segments" => 12 },
  { "type" => "box", "size" => [1.0, 0.5, 0.1], "pos" => [-3.0, 1.7, -5.02], "color" => "#ffd88a", "emissive" => "#553311" },
  # potted plant on the stage's east end
  { "type" => "cylinder", "r" => 0.35, "r2" => 0.45, "h" => 0.5, "pos" => [7.0, 1.0, -5.2], "color" => "#8a5a3a", "segments" => 8 },
  { "type" => "sphere", "r" => 0.6, "pos" => [7.0, 1.75, -5.2], "color" => "#3a7a3a", "segments" => 7 },
  # sign beside the courtyard door
  { "type" => "box", "size" => [0.12, 0.9, 0.7], "pos" => [1.6, 1.1, 5.9], "color" => "#caa96a" },
  # ceiling lamps (visual only)
  { "type" => "sphere", "r" => 0.3, "pos" => [0, 3.0, 0.5], "color" => "#ffeebb", "emissive" => "#aa8844", "segments" => 8 },
  { "type" => "sphere", "r" => 0.3, "pos" => [-4.5, 3.0, -1.5], "color" => "#ffeebb", "emissive" => "#aa8844", "segments" => 8 },
  { "type" => "sphere", "r" => 0.3, "pos" => [4.5, 3.0, -1.5], "color" => "#ffeebb", "emissive" => "#aa8844", "segments" => 8 }
]

lounge = {
  "spawn" => { "x" => 0.0, "z" => 3.0, "heading" => Math::PI },
  "background" => "#0d0a16",
  "ground_color" => "#68503c",
  "lights" => {
    "ambient" => { "color" => "#8a7a9a", "intensity" => 4.2 },
    "directional" => { "color" => "#ffd8b0", "intensity" => 5.0, "position" => [5, 10, 3] }
  },
  "camera" => { "position" => [10, 11, 10], "look_at" => [0, 0.3, 0], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 16, depth: 12, height: lounge_height, blocked: lounge_blocked),
  "props" => lounge_props,
  "interactables" => [
    { "id" => "jukebox", "name" => "Jukebox", "x" => -3.0, "z" => -5.0, "radius" => 1.5,
      "text" => "The jukebox hums and crackles. A handwritten note is taped to the glass:\n\"Out of order since '97. It only ever played one song anyway.\"" },
    { "id" => "bar", "name" => "Bar", "x" => 4.2, "z" => 2.0, "radius" => 1.5,
      "text" => "The bar is unattended. Rows of dusty bottles catch the lamplight.\nA till sits open — empty except for a single arcade token." },
    { "id" => "sofa", "name" => "Sofa", "x" => -5.0, "z" => 1.5, "radius" => 1.5,
      "text" => "A deep crimson sofa, worn to perfection.\nSomething glints between the cushions, forever out of reach." },
    { "id" => "plant", "name" => "Potted Plant", "x" => 6.4, "z" => -4.6, "radius" => 1.4,
      "text" => "Against all odds, the plant is thriving.\nSomeone has been watering it." },
    { "id" => "sign", "name" => "Wooden Sign", "x" => 1.5, "z" => 5.2, "radius" => 1.3,
      "text" => "「 COURTYARD → 」\n\"Mind the fountain. It remembers.\"" }
  ],
  "exits" => [
    { "id" => "to_courtyard", "to" => "courtyard", "x" => 0.0, "z" => 5.7, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 } }
  ]
}

# -------------------------------------------------------------- The Courtyard

courtyard_height = ->(x, z) { 0.06 * Math.sin(0.9 * x) * Math.cos(0.7 * z) }

tree_spots = [[-5.5, -5.5], [5.5, -5.5], [-5.5, 5.5], [5.5, 5.5]]
lamp_spots = [[-3.5, -3.5], [3.5, -3.5], [-3.5, 3.5], [3.5, 3.5]]

courtyard_blocked = lambda do |cx, cz|
  Math.hypot(cx, cz) < 2.2 ||                                        # fountain
    tree_spots.any? { |tx, tz| Math.hypot(cx - tx, cz - tz) < 1.2 } ||
    lamp_spots.any? { |lx, lz| Math.hypot(cx - lx, cz - lz) < 0.4 } ||
    (cx.abs > 6.0 && cz.abs < 2.0) ||                                # benches
    (cx.between?(-5.2, -2.8) && cz.between?(-6.0, -5.0))             # flower bed
end

stone = "#4a4a58"

courtyard_props = [
  # perimeter walls with a gate gap on the north side
  { "type" => "box", "size" => [6.0, 2.6, 0.4], "pos" => [-4.2, 1.3, -7.2], "color" => stone },
  { "type" => "box", "size" => [6.0, 2.6, 0.4], "pos" => [4.2, 1.3, -7.2], "color" => stone },
  { "type" => "cylinder", "r" => 0.3, "h" => 3.2, "pos" => [-1.2, 1.6, -7.2], "color" => "#6a6a7a", "segments" => 8 },
  { "type" => "cylinder", "r" => 0.3, "h" => 3.2, "pos" => [1.2, 1.6, -7.2], "color" => "#6a6a7a", "segments" => 8 },
  { "type" => "sphere", "r" => 0.38, "pos" => [-1.2, 3.3, -7.2], "color" => "#6a6a7a", "segments" => 8 },
  { "type" => "sphere", "r" => 0.38, "pos" => [1.2, 3.3, -7.2], "color" => "#6a6a7a", "segments" => 8 },
  { "type" => "box", "size" => [14.8, 2.6, 0.4], "pos" => [0, 1.3, 7.2], "color" => stone },
  { "type" => "box", "size" => [0.4, 2.6, 14.8], "pos" => [-7.2, 1.3, 0], "color" => stone },
  { "type" => "box", "size" => [0.4, 2.6, 14.8], "pos" => [7.2, 1.3, 0], "color" => stone },
  # fountain
  { "type" => "cylinder", "r" => 1.9, "h" => 0.55, "pos" => [0, 0.28, 0], "color" => "#5a5a68", "segments" => 14 },
  { "type" => "cylinder", "r" => 1.6, "h" => 0.18, "pos" => [0, 0.6, 0], "color" => "#3a6a9a", "emissive" => "#102a44", "segments" => 14 },
  { "type" => "cylinder", "r" => 0.35, "h" => 1.3, "pos" => [0, 1.0, 0], "color" => "#5a5a68", "segments" => 10 },
  { "type" => "cylinder", "r" => 0.8, "r2" => 0.9, "h" => 0.22, "pos" => [0, 1.6, 0], "color" => "#5a5a68", "segments" => 12 },
  { "type" => "sphere", "r" => 0.24, "pos" => [0, 1.85, 0], "color" => "#7ab0d8", "emissive" => "#1a3a55", "segments" => 8 },
  # trees in the corners
  *tree_spots.flat_map do |tx, tz|
    [
      { "type" => "cylinder", "r" => 0.22, "h" => 1.3, "pos" => [tx, 0.65, tz], "color" => "#4a3626", "segments" => 7 },
      { "type" => "cone", "r" => 1.15, "h" => 2.2, "pos" => [tx, 2.3, tz], "color" => "#2c5a34", "segments" => 8 },
      { "type" => "cone", "r" => 0.8, "h" => 1.5, "pos" => [tx, 3.3, tz], "color" => "#356a3c", "segments" => 8 }
    ]
  end,
  # lamp posts
  *lamp_spots.flat_map do |lx, lz|
    [
      { "type" => "cylinder", "r" => 0.07, "h" => 2.4, "pos" => [lx, 1.2, lz], "color" => "#2a2a34", "segments" => 6 },
      { "type" => "sphere", "r" => 0.24, "pos" => [lx, 2.5, lz], "color" => "#ffdd99", "emissive" => "#b08a30", "segments" => 8 }
    ]
  end,
  # benches east & west
  { "type" => "box", "size" => [0.55, 0.14, 2.4], "pos" => [6.5, 0.48, 0], "color" => wood },
  { "type" => "box", "size" => [0.14, 0.6, 2.4], "pos" => [6.85, 0.85, 0], "color" => wood },
  { "type" => "box", "size" => [0.55, 0.14, 2.4], "pos" => [-6.5, 0.48, 0], "color" => wood },
  { "type" => "box", "size" => [0.14, 0.6, 2.4], "pos" => [-6.85, 0.85, 0], "color" => wood },
  # flower bed
  { "type" => "box", "size" => [2.4, 0.4, 1.1], "pos" => [-4.0, 0.2, -5.5], "color" => "#5a4030" },
  { "type" => "sphere", "r" => 0.22, "pos" => [-4.6, 0.5, -5.5], "color" => "#d05a7a", "segments" => 6 },
  { "type" => "sphere", "r" => 0.22, "pos" => [-4.0, 0.52, -5.4], "color" => "#e0c05a", "segments" => 6 },
  { "type" => "sphere", "r" => 0.22, "pos" => [-3.4, 0.5, -5.6], "color" => "#7a5ad0", "segments" => 6 },
  # notice board by the gate
  { "type" => "box", "size" => [1.3, 0.9, 0.1], "pos" => [1.9, 1.5, -6.9], "color" => "#caa96a" },
  { "type" => "cylinder", "r" => 0.06, "h" => 1.6, "pos" => [1.4, 0.8, -6.9], "color" => "#4a3626", "segments" => 6 },
  { "type" => "cylinder", "r" => 0.06, "h" => 1.6, "pos" => [2.4, 0.8, -6.9], "color" => "#4a3626", "segments" => 6 }
]

courtyard = {
  "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 },
  "background" => "#080c1a",
  "ground_color" => "#46584a",
  "lights" => {
    "ambient" => { "color" => "#66729e", "intensity" => 2.4 },
    "directional" => { "color" => "#a8c0f0", "intensity" => 2.8, "position" => [-6, 12, 4] }
  },
  "camera" => { "position" => [10.5, 11.5, 10.5], "look_at" => [0, 0.2, 0], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 14, height: courtyard_height, blocked: courtyard_blocked),
  "props" => courtyard_props,
  "interactables" => [
    { "id" => "fountain", "name" => "Fountain", "x" => 0.0, "z" => 0.0, "radius" => 2.9,
      "text" => "Moonlight pools in the water. Coins wink up from the bottom —\nwishes in a currency nobody remembers." },
    { "id" => "board", "name" => "Notice Board", "x" => 1.9, "z" => -6.4, "radius" => 1.3,
      "kind" => "noteboard",
      "text" => "A cork board studded with pins. Anyone may leave a note." },
    { "id" => "bench", "name" => "Bench", "x" => 6.2, "z" => 0.0, "radius" => 1.4,
      "text" => "You rest a moment. Crickets. Somewhere beyond the wall,\na city that never quite loads in." },
    { "id" => "flowers", "name" => "Flower Bed", "x" => -4.0, "z" => -4.9, "radius" => 1.3,
      "text" => "Polygon petals in impossible colors.\nThey sway to a breeze the engine doesn't simulate yet." }
  ],
  "exits" => [
    { "id" => "to_lounge", "to" => "lounge", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 4.3, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------------------------- persist

[
  { slug: "lounge", name: "The Lounge", data: lounge },
  { slug: "courtyard", name: "The Courtyard", data: courtyard }
].each do |attrs|
  room = Room.find_or_initialize_by(slug: attrs[:slug])
  room.update!(name: attrs[:name], data: attrs[:data])
  puts "Seeded room: #{room.name} (#{room.data['walkmesh']['triangles'].length} walkmesh triangles)"
end

# Starter notes for the courtyard board (the old static flavor, now real
# player-style notes). Only seeded when the board is empty so reseeding never
# duplicates or clobbers what players have pinned.
courtyard_room = Room.find_by!(slug: "courtyard")
if Note.for_board(courtyard_room, "board").none?
  [
    [ "Aeris",  "Lounge open all night. The lounge is always open." ],
    [ "???",    "Lost: one arcade token. Sentimental value. Reward: another token." ]
  ].each { |author, body| Note.create!(room: courtyard_room, board_id: "board", author: author, body: body) }
  puts "Seeded #{Note.for_board(courtyard_room, 'board').count} starter notes on the courtyard board."
end
