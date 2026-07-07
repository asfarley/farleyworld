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

# Perimeter walls around a wx×wz footprint centered on the origin, open on top.
# `gaps` lists sides (:n/:s along z, :e/:w along x) that get a central doorway.
# Walls are visual only — the walkmesh edge is what actually contains players —
# so keep the mesh extent equal to wx×wz and put exits in the gaps.
def walls(wx, wz, color:, gaps: [], h: 3.0, gap_w: 2.6, thick: 0.4)
  hx = wx / 2.0
  hz = wz / 2.0
  y  = h / 2.0
  out = []
  [[:n, -hz], [:s, hz]].each do |side, z|
    if gaps.include?(side)
      half = (wx - gap_w) / 2.0
      off  = gap_w / 2.0 + half / 2.0
      out << { "type" => "box", "size" => [half, h, thick], "pos" => [-off, y, z], "color" => color }
      out << { "type" => "box", "size" => [half, h, thick], "pos" => [ off, y, z], "color" => color }
    else
      out << { "type" => "box", "size" => [wx, h, thick], "pos" => [0, y, z], "color" => color }
    end
  end
  [[:w, -hx], [:e, hx]].each do |side, x|
    if gaps.include?(side)
      half = (wz - gap_w) / 2.0
      off  = gap_w / 2.0 + half / 2.0
      out << { "type" => "box", "size" => [thick, h, half], "pos" => [x, y, -off], "color" => color }
      out << { "type" => "box", "size" => [thick, h, half], "pos" => [x, y,  off], "color" => color }
    else
      out << { "type" => "box", "size" => [thick, h, wz], "pos" => [x, y, 0], "color" => color }
    end
  end
  out
end

# A stylized palm: tapered trunk + a fan of cone fronds. Purely decorative.
def palm(x, z, trunk: "#6a5236", frond: "#2c6a34")
  [
    { "type" => "cylinder", "r" => 0.13, "r2" => 0.22, "h" => 3.0, "pos" => [x, 1.5, z], "color" => trunk, "segments" => 7 },
    { "type" => "cone", "r" => 1.4, "h" => 0.5, "pos" => [x + 0.55, 3.05, z], "color" => frond, "segments" => 5, "rot" => 0.5 },
    { "type" => "cone", "r" => 1.4, "h" => 0.5, "pos" => [x - 0.55, 3.05, z], "color" => frond, "segments" => 5, "rot" => -0.5 },
    { "type" => "cone", "r" => 1.4, "h" => 0.5, "pos" => [x, 3.05, z + 0.55], "color" => frond, "segments" => 5 },
    { "type" => "cone", "r" => 1.4, "h" => 0.5, "pos" => [x, 3.05, z - 0.55], "color" => frond, "segments" => 5 },
    { "type" => "cone", "r" => 0.9, "h" => 0.6, "pos" => [x, 3.35, z], "color" => frond, "segments" => 5 }
  ]
end

# A grid of little emissive panes stood just proud of a facade — reads as a lit
# window wall. `axis` is the facade normal (:x or :z); `sign` which way it faces.
def window_wall(cx, cy, cz, width, height, rows:, cols:, color: "#bfe3ff", emissive: "#3a5a80", axis: :z, sign: 1)
  gw = width  / cols.to_f
  gh = height / rows.to_f
  out = []
  rows.times do |r|
    cols.times do |c|
      u = -width  / 2.0 + gw * (c + 0.5)
      v = -height / 2.0 + gh * (r + 0.5)
      if axis == :z
        out << { "type" => "box", "size" => [(gw * 0.6).round(3), (gh * 0.6).round(3), 0.06],
                 "pos" => [(cx + u).round(3), (cy + v).round(3), (cz + sign * 0.03).round(3)], "color" => color, "emissive" => emissive }
      else
        out << { "type" => "box", "size" => [0.06, (gh * 0.6).round(3), (gw * 0.6).round(3)],
                 "pos" => [(cx + sign * 0.03).round(3), (cy + v).round(3), (cz + u).round(3)], "color" => color, "emissive" => emissive }
      end
    end
  end
  out
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
  # south wall, split around a gate leading to the sandstone courtyard
  { "type" => "box", "size" => [6.0, 2.6, 0.4], "pos" => [-4.4, 1.3, 7.2], "color" => stone },
  { "type" => "box", "size" => [6.0, 2.6, 0.4], "pos" => [4.4, 1.3, 7.2], "color" => stone },
  { "type" => "cylinder", "r" => 0.3, "h" => 3.2, "pos" => [-1.4, 1.6, 7.2], "color" => "#6a6a7a", "segments" => 8 },
  { "type" => "cylinder", "r" => 0.3, "h" => 3.2, "pos" => [1.4, 1.6, 7.2], "color" => "#6a6a7a", "segments" => 8 },
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
      "spawn" => { "x" => 0.0, "z" => 4.3, "heading" => Math::PI } },
    { "id" => "to_arabic", "to" => "arabic", "x" => 0.0, "z" => 6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 } }
  ]
}

# ================================================================ New zones
#
# Everything below is pure room data. Each zone follows the same recipe as the
# lounge/courtyard: a grid walkmesh (optionally shaped/holed), a pile of prop
# primitives pre-rendered as the background, fixed camera, SPACE interactables
# and walk-in exits. "Multi-level" rooms (Kowloon, Huaqiangbei) fake verticality
# with terraced walkmeshes + tall windowed facades, since the single-height
# walkmesh can't stack true floors at one x/z.

# ------------------------------------------------ The Sandstone Courtyard (hub)

sand      = "#c8a878"
sand_dk   = "#a8895f"
tile_blue = "#2f6f92"

arabic_palms   = [[5.6, 5.6], [-5.6, 5.6], [5.6, -5.6], [-5.6, -5.6]]
arabic_cols    = [[3.4, 3.4], [-3.4, 3.4], [3.4, -3.4], [-3.4, -3.4]]
arabic_benches = [[5.2, -5.2], [-5.2, 5.2]]

arabic_blocked = lambda do |cx, cz|
  Math.hypot(cx, cz) < 1.9 ||
    arabic_palms.any?   { |px, pz| Math.hypot(cx - px, cz - pz) < 0.8 } ||
    arabic_cols.any?    { |px, pz| Math.hypot(cx - px, cz - pz) < 0.5 } ||
    arabic_benches.any? { |px, pz| Math.hypot(cx - px, cz - pz) < 0.7 }
end

arabic_props = [
  *walls(14, 14, color: sand, gaps: [:n, :s, :e, :w], h: 3.2),
  # horseshoe arches over each gateway
  *[[0, -7.0, :z], [0, 7.0, :z], [-7.0, 0, :x], [7.0, 0, :x]].map do |ax, az, axis|
    { "type" => "box", "size" => (axis == :z ? [3.0, 0.6, 0.5] : [0.5, 0.6, 3.0]), "pos" => [ax, 3.1, az], "color" => sand_dk }
  end,
  # tiled floor medallion
  { "type" => "plane", "size" => [6.5, 6.5], "pos" => [0, 0.012, 0], "color" => tile_blue },
  { "type" => "plane", "size" => [3.2, 3.2], "pos" => [0, 0.018, 0], "color" => "#e8dcc0", "rot" => Math::PI / 4 },
  # central fountain (sandstone basin, glowing water)
  { "type" => "cylinder", "r" => 1.9, "h" => 0.55, "pos" => [0, 0.28, 0], "color" => sand_dk, "segments" => 16 },
  { "type" => "cylinder", "r" => 1.6, "h" => 0.16, "pos" => [0, 0.6, 0], "color" => "#3a9ac0", "emissive" => "#164055", "segments" => 16 },
  { "type" => "cylinder", "r" => 0.3, "h" => 1.2, "pos" => [0, 1.0, 0], "color" => sand, "segments" => 10 },
  { "type" => "cylinder", "r" => 0.75, "r2" => 0.85, "h" => 0.2, "pos" => [0, 1.55, 0], "color" => sand, "segments" => 12 },
  { "type" => "sphere", "r" => 0.22, "pos" => [0, 1.8, 0], "color" => "#7ad0e8", "emissive" => "#1a4a55", "segments" => 8 },
  # ornamental columns (foreground occluders)
  *arabic_cols.flat_map do |cx, cz|
    [
      { "type" => "cylinder", "r" => 0.32, "h" => 3.0, "pos" => [cx, 1.5, cz], "color" => "#ddd0b4", "segments" => 10 },
      { "type" => "cylinder", "r" => 0.42, "r2" => 0.32, "h" => 0.4, "pos" => [cx, 3.1, cz], "color" => sand_dk, "segments" => 10 }
    ]
  end,
  *arabic_palms.flat_map { |px, pz| palm(px, pz) },
  # benches
  *arabic_benches.flat_map do |bx, bz|
    [
      { "type" => "box", "size" => [1.6, 0.16, 0.6], "pos" => [bx, 0.42, bz], "color" => "#b08a5a" },
      { "type" => "box", "size" => [1.6, 0.5, 0.14], "pos" => [bx, 0.7, bz - 0.25], "color" => "#9a7648" }
    ]
  end,
  # hanging lanterns near the arches
  *[[-3.4, 3.4], [3.4, -3.4]].map { |lx, lz| { "type" => "sphere", "r" => 0.22, "pos" => [lx, 2.6, lz], "color" => "#ffcf7a", "emissive" => "#b07a20", "segments" => 8 } }
]

arabic = {
  "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 },
  "background" => "#1a1220",
  "ground_color" => "#b89a6c",
  "lights" => {
    "ambient" => { "color" => "#b09878", "intensity" => 3.4 },
    "directional" => { "color" => "#ffe2b0", "intensity" => 4.2, "position" => [6, 11, 4] }
  },
  "camera" => { "position" => [11, 12, 11], "look_at" => [0, 0.4, 0], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 14, blocked: arabic_blocked),
  "props" => arabic_props,
  "interactables" => [
    { "id" => "fountain", "name" => "Fountain", "x" => 0.0, "z" => 0.0, "radius" => 2.7,
      "text" => "Cool water spills over sandstone. The tilework spells a word\nin a script that rearranges itself when you look away." },
    { "id" => "bench", "name" => "Shaded Bench", "x" => 5.2, "z" => -5.2, "radius" => 1.4,
      "text" => "The stone is warm. Date palms rustle overhead, dropping\nlong blue shadows across the courtyard." },
    { "id" => "arch", "name" => "Horseshoe Arch", "x" => 0.0, "z" => -6.4, "radius" => 1.4,
      "text" => "Four gateways, four elsewheres. Each arch frames a\ndifferent impossible afternoon." }
  ],
  "exits" => [
    { "id" => "to_courtyard", "to" => "courtyard", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 5.0, "heading" => Math::PI } },
    { "id" => "to_rainforest", "to" => "rainforest", "x" => 6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => -6.2, "z" => 0.0, "heading" => Math::PI / 2 } },
    { "id" => "to_foodcourt", "to" => "foodcourt", "x" => -6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => 1.5, "z" => -7.0, "heading" => 0.0 } },
    { "id" => "to_showerworld", "to" => "showerworld", "x" => 0.0, "z" => 6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 } }
  ]
}

# ------------------------------------------------ Megalithic Rainforest

rainforest_height = ->(x, z) { 0.16 * Math.sin(0.5 * x) * Math.cos(0.42 * z) }

rain_trees = [[-6.0, -4.0], [-4.2, -1.5], [-6.2, 2.5], [-3.0, 4.7], [6.0, -3.2],
              [3.6, -4.6], [6.6, 1.6], [2.6, 5.6], [-6.6, 5.0], [7.0, 5.4], [-2.0, -5.6]]

rain_blocked = lambda do |cx, cz|
  rain_trees.any? { |tx, tz| Math.hypot(cx - tx, cz - tz) < 1.0 }
end

rainforest_props = [
  # megalithic retaining wall along the north edge, split for the passage up
  { "type" => "box", "size" => [6.0, 4.0, 0.9], "pos" => [-4.6, 2.0, -6.8], "color" => "#7a746a", "rot" => 0.03 },
  { "type" => "box", "size" => [6.0, 4.0, 0.9], "pos" => [4.6, 2.0, -6.8], "color" => "#726c62", "rot" => -0.03 },
  { "type" => "box", "size" => [2.4, 2.2, 0.8], "pos" => [-3.2, 1.1, -6.5], "color" => "#847e72" },
  { "type" => "box", "size" => [2.2, 1.6, 0.8], "pos" => [3.4, 0.8, -6.5], "color" => "#847e72" },
  # cenote: a rimmed sinkhole in the SE, dark water far below
  { "type" => "cylinder", "r" => 2.0, "r2" => 2.4, "h" => 0.5, "pos" => [5.0, 0.25, 4.0], "color" => "#6a6258", "segments" => 16 },
  { "type" => "cylinder", "r" => 1.7, "h" => 0.2, "pos" => [5.0, -0.8, 4.0], "color" => "#0e2c3a", "emissive" => "#06202c", "segments" => 16 },
  # rainforest canopy — trunks + layered spheres
  *rain_trees.flat_map do |tx, tz|
    [
      { "type" => "cylinder", "r" => 0.24, "h" => 3.4, "pos" => [tx, 1.7, tz], "color" => "#4a3a2a", "segments" => 6 },
      { "type" => "sphere", "r" => 1.5, "pos" => [tx, 3.8, tz], "color" => "#245c2c", "segments" => 7 },
      { "type" => "sphere", "r" => 1.1, "pos" => [tx + 0.6, 4.4, tz - 0.4], "color" => "#2e6e36", "segments" => 6 }
    ]
  end,
  # ferns / undergrowth dabs
  *[[-1.0, -2.0], [1.5, 1.0], [-2.5, 2.0], [3.0, 2.5], [-4.5, -3.5]].map do |fx, fz|
    { "type" => "cone", "r" => 0.7, "h" => 0.8, "pos" => [fx, 0.4, fz], "color" => "#3a8a3e", "segments" => 5 }
  end,
  # a carved idol stone standing in the clearing
  { "type" => "box", "size" => [0.8, 1.8, 0.8], "pos" => [-1.0, 0.9, 0.0], "color" => "#8a8478" },
  { "type" => "sphere", "r" => 0.45, "pos" => [-1.0, 2.0, 0.0], "color" => "#948e82", "segments" => 6 }
]

rainforest = {
  "spawn" => { "x" => 0.0, "z" => 3.0, "heading" => Math::PI },
  "background" => "#0c1a12",
  "ground_color" => "#3d5836",
  "lights" => {
    "ambient" => { "color" => "#7ea070", "intensity" => 3.0 },
    "directional" => { "color" => "#cfeeb0", "intensity" => 3.6, "position" => [-4, 12, 3] }
  },
  "camera" => { "position" => [11, 12.5, 11], "look_at" => [0, 0.4, 0], "fov" => 47 },
  "walkmesh" => grid_walkmesh(width: 16, depth: 14, height: rainforest_height, blocked: rain_blocked),
  "props" => rainforest_props,
  "interactables" => [
    { "id" => "cenote", "name" => "Cenote", "x" => 5.0, "z" => 4.0, "radius" => 1.8,
      "text" => "The ground opens onto a shaft of black water far below.\nCold air breathes up out of it. A rope ladder descends." },
    { "id" => "idol", "name" => "Carved Idol", "x" => -1.0, "z" => 0.0, "radius" => 1.4,
      "text" => "A squat stone figure, features worn to suggestion.\nMoss fills the grooves of an inscription no one recorded." },
    { "id" => "canopy", "name" => "Canopy", "x" => 0.0, "z" => 5.0, "radius" => 1.6,
      "text" => "Somewhere above, unseen birds trade three-note calls.\nThe humidity renders as a faint green haze." }
  ],
  "exits" => [
    { "id" => "to_arabic", "to" => "arabic", "x" => -7.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => 5.4, "z" => 0.0, "heading" => -Math::PI / 2 } },
    { "id" => "to_megalith", "to" => "megalith", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 5.0, "heading" => Math::PI } },
    { "id" => "to_cenote", "to" => "cenote", "x" => 5.0, "z" => 4.0, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 3.8, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------ The Cenote (cave)

cenote_blocked = lambda do |cx, cz|
  Math.hypot(cx, cz) < 3.0 ||                      # the water
    (cx.abs > 5.2 || cz.abs > 5.2)                 # rough cavern walls
end

cenote_props = [
  # cavern water disc
  { "type" => "cylinder", "r" => 3.0, "h" => 0.3, "pos" => [0, -0.15, 0], "color" => "#12475e", "emissive" => "#082530", "segments" => 20 },
  { "type" => "cylinder", "r" => 2.4, "h" => 0.12, "pos" => [0, 0.02, 0], "color" => "#1d6a86", "emissive" => "#0c3a4c", "segments" => 20 },
  # ragged rock walls
  *(0...10).map do |i|
    a = i * (2 * Math::PI / 10)
    { "type" => "box", "size" => [1.8, 4.0, 1.8], "pos" => [(6.4 * Math.cos(a)).round(3), 2.0, (6.4 * Math.sin(a)).round(3)], "color" => "#3a352f", "rot" => a }
  end,
  # a shaft of daylight from the sinkhole mouth
  { "type" => "cylinder", "r" => 1.1, "h" => 6.0, "pos" => [1.4, 3.0, -1.4], "color" => "#dfeecf", "emissive" => "#9ab07a", "segments" => 10 },
  # stalactites hanging into frame (foreground occluders)
  { "type" => "cone", "r" => 0.4, "h" => 2.2, "pos" => [-2.8, 4.3, 2.4], "color" => "#5a544c", "segments" => 6, "rot" => Math::PI },
  { "type" => "cone", "r" => 0.3, "h" => 1.6, "pos" => [3.0, 4.6, -2.0], "color" => "#524c44", "segments" => 6, "rot" => Math::PI },
  { "type" => "cone", "r" => 0.5, "h" => 2.6, "pos" => [0.5, 4.4, 3.4], "color" => "#5a544c", "segments" => 6, "rot" => Math::PI },
  # a stone offering shelf on the north ledge
  { "type" => "box", "size" => [1.4, 0.5, 0.7], "pos" => [-3.8, 0.25, -3.8], "color" => "#4a443c" },
  { "type" => "sphere", "r" => 0.18, "pos" => [-3.8, 0.6, -3.8], "color" => "#c8a84a", "emissive" => "#5a4410", "segments" => 6 }
]

cenote = {
  "spawn" => { "x" => 0.0, "z" => 3.8, "heading" => Math::PI },
  "background" => "#05101a",
  "ground_color" => "#2e2a24",
  "lights" => {
    "ambient" => { "color" => "#4a6a80", "intensity" => 2.2 },
    "directional" => { "color" => "#bfe0ff", "intensity" => 2.6, "position" => [2, 12, -2] }
  },
  "camera" => { "position" => [9, 11, 9], "look_at" => [0, 0.0, 0], "fov" => 48 },
  "walkmesh" => grid_walkmesh(width: 12, depth: 12, blocked: cenote_blocked),
  "props" => cenote_props,
  "interactables" => [
    { "id" => "water", "name" => "Black Water", "x" => 0.0, "z" => 2.6, "radius" => 1.6,
      "text" => "The pool is perfectly still and perfectly dark. Your reflection\narrives a half-second late." },
    { "id" => "offering", "name" => "Offering Shelf", "x" => -3.4, "z" => -3.4, "radius" => 1.4,
      "text" => "Coins, a jade bead, a house key. Left by people who\nneeded to leave something down here." }
  ],
  "exits" => [
    { "id" => "to_rainforest", "to" => "rainforest", "x" => 0.0, "z" => -5.0, "radius" => 0.9,
      "spawn" => { "x" => 5.0, "z" => 1.8, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------ The Megalithic Complex

megalith_height = lambda do |_x, z|
  if z <= -3.0 then 1.2
  elsif z <= -1.5 then 1.2 * ((-1.5 - z) / 1.5)
  else 0.0
  end
end

mega_machines = [[-3.0, -5.0], [3.0, -5.0], [5.2, -4.2]]

megalith_blocked = lambda do |cx, cz|
  mega_machines.any? { |mx, mz| Math.hypot(cx - mx, cz - mz) < 1.1 } ||
    (cx.abs > 6.5 && cz.between?(-1.0, 5.0))         # flanking polygonal walls
end

megalith_props = [
  # large-scale polygonal masonry — big irregular fitted blocks, two courses
  *[[-6.0, 0.9, 2.0], [-6.0, 0.9, 3.6], [-6.2, 0.9, 0.4], [6.0, 0.9, 2.0], [6.0, 0.9, 3.6], [6.2, 0.9, 0.4]].each_slice(1).flat_map do |(bx, by, bz)|
    [{ "type" => "box", "size" => [1.4, 1.7, 1.5], "pos" => [bx, by, bz], "color" => "#8a8276", "rot" => (bx * 0.05) }]
  end,
  *[[-6.0, 2.4, 1.2], [-6.0, 2.4, 3.0], [6.0, 2.4, 1.2], [6.0, 2.4, 3.0]].map do |bx, by, bz|
    { "type" => "box", "size" => [1.7, 1.3, 1.5], "pos" => [bx, by, bz], "color" => "#948c80", "rot" => 0.04 }
  end,
  # the raised terrace edge (retaining course)
  { "type" => "box", "size" => [13.0, 0.4, 0.6], "pos" => [0, 1.2, -1.5], "color" => "#7a746a" },
  # a standing monolith on the terrace
  { "type" => "box", "size" => [1.0, 3.4, 0.7], "pos" => [-3.0, 2.9, -5.0], "color" => "#9a9284", "rot" => 0.02 },
  # industrial-looking geometry: a stepped ziggurat block + tank + ducting
  { "type" => "box", "size" => [2.4, 1.6, 2.4], "pos" => [3.0, 2.0, -5.0], "color" => "#6e6a64" },
  { "type" => "box", "size" => [1.6, 0.8, 1.6], "pos" => [3.0, 3.2, -5.0], "color" => "#5e5a54" },
  { "type" => "cylinder", "r" => 0.9, "h" => 2.6, "pos" => [5.2, 2.5, -4.2], "color" => "#8a8a92", "segments" => 12 },
  { "type" => "cylinder", "r" => 0.95, "r2" => 0.6, "h" => 0.4, "pos" => [5.2, 4.0, -4.2], "color" => "#6a6a72", "segments" => 12 },
  { "type" => "box", "size" => [4.0, 0.4, 0.4], "pos" => [4.1, 3.4, -4.2], "color" => "#4a4a52" },
  # foreground trilithon framing the courtyard entrance
  { "type" => "box", "size" => [0.8, 3.2, 0.8], "pos" => [-1.8, 1.6, 5.2], "color" => "#8a8276" },
  { "type" => "box", "size" => [0.8, 3.2, 0.8], "pos" => [1.8, 1.6, 5.2], "color" => "#8a8276" },
  { "type" => "box", "size" => [4.4, 0.8, 0.9], "pos" => [0, 3.4, 5.2], "color" => "#7e766a" }
]

megalith = {
  "spawn" => { "x" => 0.0, "z" => 4.5, "heading" => Math::PI },
  "background" => "#141014",
  "ground_color" => "#7a6a56",
  "lights" => {
    "ambient" => { "color" => "#9a8a78", "intensity" => 3.0 },
    "directional" => { "color" => "#ffcf9a", "intensity" => 4.0, "position" => [7, 10, 2] }
  },
  "camera" => { "position" => [12, 12.5, 11], "look_at" => [0, 0.6, 0], "fov" => 47 },
  "walkmesh" => grid_walkmesh(width: 16, depth: 14, height: megalith_height, blocked: megalith_blocked),
  "props" => megalith_props,
  "interactables" => [
    { "id" => "wall", "name" => "Polygonal Wall", "x" => -6.0, "z" => 2.5, "radius" => 1.6,
      "text" => "Twelve-sided blocks fitted without mortar, seams so tight\nno blade enters. Nobody agrees how it was cut." },
    { "id" => "monolith", "name" => "Standing Monolith", "x" => -3.0, "z" => -3.8, "radius" => 1.6,
      "text" => "A single dressed stone, taller than three players.\nIt hums almost below hearing when you stand close." },
    { "id" => "machine", "name" => "The Apparatus", "x" => 4.0, "z" => -3.6, "radius" => 1.7,
      "text" => "Tanks, ducting, a stepped housing — unmistakably machinery,\nbuilt from the same ancient stone as everything else." }
  ],
  "exits" => [
    { "id" => "to_rainforest", "to" => "rainforest", "x" => 0.0, "z" => 6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 } },
    { "id" => "to_dolmen", "to" => "dolmen", "x" => -7.6, "z" => -2.5, "radius" => 0.9,
      "spawn" => { "x" => 5.0, "z" => 0.0, "heading" => -Math::PI / 2 } }
  ]
}

# ------------------------------------------------ Megalithic Dolmen Viewpoint

dolmen_height = ->(_x, z) { -0.05 * (z + 6.0) }   # gentle slope toward the edge

dolmen_blocked = lambda do |cx, cz|
  (Math.hypot(cx + 1.2, cz + 2.0) < 0.6) ||        # dolmen upright
    (Math.hypot(cx - 1.2, cz + 2.0) < 0.6) ||      # dolmen upright
    (cz > 4.6)                                      # cliff edge (low wall)
end

dolmen_props = [
  # the dolmen: two uprights + a tilted capstone
  { "type" => "box", "size" => [0.9, 2.2, 0.9], "pos" => [-1.2, 1.1, -2.0], "color" => "#8e867a" },
  { "type" => "box", "size" => [0.9, 2.2, 0.9], "pos" => [1.2, 1.1, -2.0], "color" => "#847c70" },
  { "type" => "box", "size" => [3.6, 0.7, 2.0], "pos" => [0, 2.5, -2.0], "color" => "#9a9286", "rot" => 0.06 },
  # cairn to one side
  { "type" => "sphere", "r" => 0.6, "pos" => [3.6, 0.4, -1.0], "color" => "#7a746a", "segments" => 6 },
  { "type" => "sphere", "r" => 0.4, "pos" => [3.6, 0.9, -1.0], "color" => "#847e72", "segments" => 6 },
  { "type" => "sphere", "r" => 0.25, "pos" => [3.6, 1.3, -1.0], "color" => "#8e867a", "segments" => 6 },
  # low drystone wall along the cliff edge
  { "type" => "box", "size" => [14.0, 0.6, 0.4], "pos" => [0, 0.3, 5.0], "color" => "#6e685e" },
  # a viewing bench facing out
  { "type" => "box", "size" => [1.8, 0.16, 0.6], "pos" => [-3.5, 0.42, 3.4], "color" => "#7a5f3c" },
  { "type" => "box", "size" => [1.8, 0.5, 0.14], "pos" => [-3.5, 0.7, 3.66], "color" => "#6a4f30" },
  # distant hills beyond the drop (scenery past the mesh — never walked)
  *[[-8, 9, 3.2], [-2, 10.5, 4.0], [5, 9.5, 3.4], [10, 8.5, 2.8]].map do |mx, mz, mh|
    { "type" => "cone", "r" => mh, "h" => mh * 1.6, "pos" => [mx, mh * 0.4, mz], "color" => "#3a4a5a", "segments" => 6 }
  end
]

dolmen = {
  "spawn" => { "x" => 0.0, "z" => 3.0, "heading" => 0.0 },
  "background" => "#20263a",
  "ground_color" => "#5a6a48",
  "lights" => {
    "ambient" => { "color" => "#8a86a0", "intensity" => 3.0 },
    "directional" => { "color" => "#ffb87a", "intensity" => 4.2, "position" => [-8, 7, 6] }
  },
  "camera" => { "position" => [9, 9, 12], "look_at" => [0, 0.6, -1.0], "fov" => 50 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 12, height: dolmen_height, blocked: dolmen_blocked),
  "props" => dolmen_props,
  "interactables" => [
    { "id" => "dolmen", "name" => "The Dolmen", "x" => 0.0, "z" => -2.0, "radius" => 1.8,
      "text" => "Two uprights and a capstone, balanced five thousand years.\nThrough the gap you can see exactly one star, even at noon." },
    { "id" => "view", "name" => "The Overlook", "x" => 0.0, "z" => 4.3, "radius" => 1.8,
      "text" => "Ridgelines fold away into blue distance. The render\nfog does the heavy lifting, and you're grateful for it." }
  ],
  "exits" => [
    { "id" => "to_megalith", "to" => "megalith", "x" => 6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => -6.4, "z" => 0.0, "heading" => Math::PI / 2 } }
  ]
}

# ------------------------------------------------ FoodCourt Ravine

# River runs down the west side (x < -1), a walkway promenade on the east.
food_blocked = lambda do |cx, _cz|
  cx < -1.0 ||                                      # the river
    cx > 3.3                                         # stall frontage
end

# Restaurant stalls line the promenade; each is a colored booth + awning + sign.
food_stalls = [
  [3.7, -6.0, "#c0432f", "#ff8a6a"], [3.7, -3.0, "#2f7ac0", "#7ab8ff"],
  [3.7,  0.0, "#c0a02f", "#ffe07a"], [3.7,  3.0, "#2fa05a", "#7affb0"],
  [3.7,  6.0, "#8a2fc0", "#c88aff"]
]
# Across the river, a second row (pure scenery behind the water).
food_far = [[-3.6, -5.0, "#c06a2f"], [-3.6, -1.5, "#2f9ac0"], [-3.6, 2.0, "#a02f6a"], [-3.6, 5.5, "#5aa02f"]]

food_props = [
  # ravine cliff walls
  { "type" => "box", "size" => [0.8, 5.0, 18.0], "pos" => [4.2, 2.5, 0], "color" => "#5a5048" },
  { "type" => "box", "size" => [0.8, 5.0, 18.0], "pos" => [-4.2, 2.5, 0], "color" => "#544a42" },
  # the river
  { "type" => "box", "size" => [3.0, 0.25, 18.0], "pos" => [-2.5, -0.12, 0], "color" => "#1f6f8c", "emissive" => "#0c3444" },
  # little boats drifting to the restaurants
  *[[-2.5, -4.0], [-2.2, 1.0], [-2.8, 5.0]].map do |bx, bz|
    { "type" => "box", "size" => [0.9, 0.3, 1.8], "pos" => [bx, 0.15, bz], "color" => "#7a5230" }
  end,
  # promenade stalls
  *food_stalls.flat_map do |sx, sz, body, sign|
    [
      { "type" => "box", "size" => [1.4, 1.8, 1.8], "pos" => [sx, 0.9, sz], "color" => body },
      { "type" => "box", "size" => [1.8, 0.2, 2.2], "pos" => [sx - 0.5, 1.9, sz], "color" => "#f0f0f0", "rot" => 0.0 },
      { "type" => "box", "size" => [0.1, 0.5, 1.4], "pos" => [sx - 1.2, 1.4, sz], "color" => sign, "emissive" => sign },
      { "type" => "cylinder", "r" => 0.12, "h" => 1.9, "pos" => [sx - 1.35, 0.95, sz - 0.9], "color" => "#3a3a3a", "segments" => 6 }
    ]
  end,
  # far row (scenery)
  *food_far.flat_map do |sx, sz, body|
    [
      { "type" => "box", "size" => [1.3, 1.6, 1.6], "pos" => [sx, 0.8, sz], "color" => body },
      { "type" => "box", "size" => [1.6, 0.18, 2.0], "pos" => [sx + 0.5, 1.7, sz], "color" => "#e8e8e8" }
    ]
  end,
  # string lights over the promenade
  *(-7..6).step(2).flat_map do |lz|
    [{ "type" => "sphere", "r" => 0.12, "pos" => [1.0, 2.6, lz], "color" => "#ffd88a", "emissive" => "#b08830", "segments" => 6 }]
  end
]

foodcourt = {
  "spawn" => { "x" => 1.5, "z" => 0.0, "heading" => 0.0 },
  "background" => "#120e14",
  "ground_color" => "#6a5f52",
  "lights" => {
    "ambient" => { "color" => "#9a8a76", "intensity" => 3.2 },
    "directional" => { "color" => "#ffd8a0", "intensity" => 3.4, "position" => [4, 11, 6] }
  },
  "camera" => { "position" => [2.5, 13, 14], "look_at" => [0, 0.4, -1.0], "fov" => 55 },
  "walkmesh" => grid_walkmesh(width: 8, depth: 18, blocked: food_blocked),
  "props" => food_props,
  "interactables" => [
    { "id" => "noodles", "name" => "Noodle Stall", "x" => 3.0, "z" => 0.0, "radius" => 1.5,
      "text" => "Steam, chili oil, the clatter of a wok. The menu is\nforty items long and every one costs one arcade token." },
    { "id" => "river", "name" => "The River", "x" => 0.5, "z" => -3.0, "radius" => 1.6,
      "text" => "A flat-bottomed boat noses up to a jetty, laden with\ncovered dishes. It casts off the moment you look away." },
    { "id" => "grill", "name" => "Skewer Grill", "x" => 3.0, "z" => 6.0, "radius" => 1.5,
      "text" => "Charcoal smoke curls up the ravine. The grillmaster\nnods at you without ever quite making eye contact." }
  ],
  "exits" => [
    { "id" => "to_arabic", "to" => "arabic", "x" => 1.5, "z" => -8.4, "radius" => 0.9,
      "spawn" => { "x" => -5.4, "z" => 0.0, "heading" => Math::PI / 2 } },
    { "id" => "to_kowloon", "to" => "kowloon", "x" => 1.5, "z" => 8.4, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 } }
  ]
}

# ------------------------------------------------ Kowloon (multi-level)

# A low central deck reachable by a ramp fakes a second level; tall tenement
# facades all around sell the vertical density.
kowloon_height = lambda do |x, z|
  if x.between?(-2.5, 2.5) && z.between?(1.0, 5.5) then 0.9      # raised deck
  elsif x.between?(-2.5, 2.5) && z.between?(-0.5, 1.0) then 0.9 * ((z + 0.5) / 1.5)  # ramp
  else 0.0
  end
end

kowloon_pillars = [[-2.5, -2.0], [2.5, -2.0]]

kowloon_blocked = lambda do |cx, cz|
  kowloon_pillars.any? { |px, pz| Math.hypot(cx - px, cz - pz) < 0.6 }
end

# perimeter tenement block on one side
def tenement(cx, cz, w, h, d, body, axis, sign)
  [
    { "type" => "box", "size" => [w, h, d], "pos" => [cx, h / 2.0, cz], "color" => body },
    *window_wall(cx, h / 2.0 + 0.2, cz, (axis == :z ? w - 0.6 : d - 0.6), h - 1.2,
                 rows: (h / 1.4).floor, cols: ((axis == :z ? w : d) / 1.3).floor,
                 color: "#ffdca0", emissive: "#7a5a2a", axis: axis, sign: sign)
  ]
end

kowloon_props = [
  # tenement facades on the north, east and south-ish, gaps left for exits
  *tenement(-4.6, -6.6, 5.0, 7.0, 1.0, "#3a3630", :z, 1),
  *tenement(4.6, -6.6, 5.0, 6.0, 1.0, "#403a33", :z, 1),
  *tenement(-6.7, 4.6, 1.0, 6.5, 5.0, "#38332d", :x, 1),
  *tenement(6.7, 4.6, 1.0, 7.0, 5.0, "#3d3730", :x, -1),
  *tenement(4.6, 6.7, 5.0, 5.5, 1.0, "#3a352f", :z, -1),
  *tenement(-4.6, 6.7, 5.0, 6.0, 1.0, "#413b34", :z, -1),
  # raised market deck slab + support pillars (occluders)
  { "type" => "box", "size" => [5.4, 0.3, 4.8], "pos" => [0, 0.9, 3.25], "color" => "#4a443c" },
  *kowloon_pillars.map { |px, pz| { "type" => "cylinder", "r" => 0.35, "h" => 3.4, "pos" => [px, 1.7, pz], "color" => "#2e2a26", "segments" => 8 } },
  # neon signs jutting into the alley
  { "type" => "box", "size" => [0.15, 1.6, 2.4], "pos" => [-3.4, 3.2, -4.0], "color" => "#ff2f6a", "emissive" => "#ff2f6a" },
  { "type" => "box", "size" => [2.4, 1.0, 0.15], "pos" => [3.0, 4.2, -3.4], "color" => "#2fd0ff", "emissive" => "#2fd0ff" },
  { "type" => "box", "size" => [0.15, 1.2, 1.6], "pos" => [3.6, 2.4, 3.0], "color" => "#7aff2f", "emissive" => "#7aff2f" },
  { "type" => "box", "size" => [1.8, 0.8, 0.15], "pos" => [-3.0, 5.0, 3.0], "color" => "#ffcf2f", "emissive" => "#ffcf2f" },
  # a food cart on the deck + hanging AC units and wires (occluders)
  { "type" => "box", "size" => [1.4, 0.9, 0.9], "pos" => [0, 1.55, 3.4], "color" => "#8a3a2a" },
  { "type" => "box", "size" => [0.6, 0.6, 0.5], "pos" => [-5.6, 3.5, -2.0], "color" => "#c8c8c8" },
  { "type" => "box", "size" => [0.6, 0.6, 0.5], "pos" => [5.6, 4.2, 1.0], "color" => "#bcbcbc" }
]

kowloon = {
  "spawn" => { "x" => 0.0, "z" => -4.5, "heading" => 0.0 },
  "background" => "#0a0810",
  "ground_color" => "#33302b",
  "lights" => {
    "ambient" => { "color" => "#5a5a72", "intensity" => 2.9 },
    "directional" => { "color" => "#b0a0d0", "intensity" => 2.4, "position" => [3, 12, -2] }
  },
  "camera" => { "position" => [11, 13, 11], "look_at" => [0, 0.8, 1.0], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 14, height: kowloon_height, blocked: kowloon_blocked),
  "props" => kowloon_props,
  "interactables" => [
    { "id" => "sign", "name" => "Neon Thicket", "x" => -3.0, "z" => -3.4, "radius" => 1.6,
      "text" => "Signs stacked on signs in five scripts, some for shops\nthat closed decades ago. The alley never sees the sky." },
    { "id" => "cart", "name" => "Deck Food Cart", "x" => 0.0, "z" => 2.6, "radius" => 1.5,
      "text" => "Up the ramp, a cart sells something fried and unlabeled.\nThe upper deck creaks under the weight of the whole block." },
    { "id" => "mailboxes", "name" => "Mailboxes", "x" => -5.6, "z" => -4.0, "radius" => 1.5,
      "text" => "A rusted wall of tiny mailboxes, hundreds of them,\nmore residences than the building could possibly hold." }
  ],
  "exits" => [
    { "id" => "to_foodcourt", "to" => "foodcourt", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 1.5, "z" => 7.0, "heading" => Math::PI } },
    { "id" => "to_huaqiangbei", "to" => "huaqiangbei", "x" => 6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => -6.4, "z" => 0.0, "heading" => Math::PI / 2 } },
    { "id" => "to_shanty", "to" => "shanty", "x" => -6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => 5.0, "z" => 0.0, "heading" => -Math::PI / 2 } },
    { "id" => "to_alley", "to" => "alley", "x" => 0.0, "z" => 6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 4.6, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------ Huaqiangbei electronics market

# Ground aisles + a raised mezzanine terrace (reached by an escalator ramp) fake
# the multi-floor market.
huaqiangbei_height = lambda do |x, z|
  if x >= 4.0 && z.between?(-4.0, 4.0) then 1.0                 # mezzanine
  elsif x.between?(2.5, 4.0) && z.between?(-1.0, 1.0) then 1.0 * ((x - 2.5) / 1.5)  # escalator
  else 0.0
  end
end

# Two rows of vendor booths with an aisle between; keep the west entrance aisle
# and the escalator mouth clear.
hqb_booths = []
[-3.0, 3.0].each { |bz| [-4.5, -2.0, 0.5].each { |bx| hqb_booths << [bx, bz] } }

hqb_blocked = lambda do |cx, cz|
  hqb_booths.any? { |bx, bz| (cx - bx).abs < 0.85 && (cz - bz).abs < 0.85 }
end

hqb_props = [
  *walls(16, 14, color: "#4a4e56", gaps: [:w], h: 3.6),
  # ceiling grid of fluorescent panels
  *(-6..6).step(3).flat_map do |lx|
    (-4..4).step(4).map { |lz| { "type" => "box", "size" => [2.2, 0.1, 1.2], "pos" => [lx, 3.4, lz], "color" => "#ffffff", "emissive" => "#8a8a9a" } }
  end,
  # vendor booths: counter + glass case + lit component wall behind
  *hqb_booths.flat_map do |bx, bz|
    [
      { "type" => "box", "size" => [1.5, 1.0, 1.5], "pos" => [bx, 0.5, bz], "color" => "#c8c2b0" },
      { "type" => "box", "size" => [1.4, 0.2, 1.4], "pos" => [bx, 1.05, bz], "color" => "#8ad8ff", "emissive" => "#2a5a70" },
      { "type" => "box", "size" => [1.5, 0.6, 0.12], "pos" => [bx, 1.6, bz + (bz.negative? ? -0.7 : 0.7)], "color" => "#2f8a4a", "emissive" => "#124a20" }
    ]
  end,
  # mezzanine slab + railing
  { "type" => "box", "size" => [3.6, 0.3, 8.0], "pos" => [6.0, 1.0, 0], "color" => "#5a5e66" },
  { "type" => "box", "size" => [0.1, 0.6, 8.0], "pos" => [4.2, 1.5, 0], "color" => "#8a8e96" },
  # escalator hint (striped ramp)
  { "type" => "box", "size" => [1.4, 0.1, 2.2], "pos" => [3.25, 0.55, 0], "color" => "#3a3e46" },
  # a big lit signboard over the entrance
  { "type" => "box", "size" => [0.2, 1.2, 5.0], "pos" => [-7.7, 2.6, 0], "color" => "#ff5a2f", "emissive" => "#ff5a2f" }
]

huaqiangbei = {
  "spawn" => { "x" => 0.0, "z" => 0.0, "heading" => Math::PI / 2 },
  "background" => "#0e1016",
  "ground_color" => "#5a5850",
  "lights" => {
    "ambient" => { "color" => "#b0b4c0", "intensity" => 3.6 },
    "directional" => { "color" => "#e8f0ff", "intensity" => 2.6, "position" => [-4, 12, 3] }
  },
  "camera" => { "position" => [-11, 12.5, 11], "look_at" => [1.0, 0.6, 0], "fov" => 48 },
  "walkmesh" => grid_walkmesh(width: 16, depth: 14, height: huaqiangbei_height, blocked: hqb_blocked),
  "props" => hqb_props,
  "interactables" => [
    { "id" => "chips", "name" => "Component Booth", "x" => -4.5, "z" => -1.8, "radius" => 1.5,
      "text" => "Bins of chips, connectors, mystery modules by the kilo.\nThe vendor can find any part ever made in under a minute." },
    { "id" => "mezzanine", "name" => "Mezzanine", "x" => 5.6, "z" => 0.0, "radius" => 1.6,
      "text" => "Up the escalator, another whole floor of booths, and above\nthat another, repeating past where the render gives up." },
    { "id" => "repair", "name" => "Repair Counter", "x" => 0.5, "z" => 2.8, "radius" => 1.5,
      "text" => "A phone in forty pieces under a magnifier lamp. It will be\nwhole and faster than new by the time you finish reading this." }
  ],
  "exits" => [
    { "id" => "to_kowloon", "to" => "kowloon", "x" => -7.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => 5.4, "z" => 0.0, "heading" => -Math::PI / 2 } }
  ]
}

# ------------------------------------------------ ShowerWorld (tiled labyrinth)

# A guaranteed-open central corridor (|x| < 1) links the north and south exits;
# partitions branch off it into a shallow maze.
shower_parts = [
  [-3.0, -4.0, 3.0, 0.3], [3.0, -2.0, 3.0, 0.3], [-3.5, 0.0, 2.0, 0.3],
  [3.5, 2.0, 2.0, 0.3], [-2.5, 3.5, 2.5, 0.3], [2.0, 4.5, 3.0, 0.3],
  [-4.5, -1.5, 0.3, 3.0], [4.5, 1.0, 0.3, 3.5]
]

shower_blocked = lambda do |cx, cz|
  shower_parts.any? do |px, pz, w, d|
    (cx - px).abs < w / 2.0 + 0.3 && (cz - pz).abs < d / 2.0 + 0.3
  end
end

shower_props = [
  *walls(14, 14, color: "#2f7a6a", gaps: [:n, :s], h: 3.0),
  # wet tiled floor
  { "type" => "plane", "size" => [13.6, 13.6], "pos" => [0, 0.01, 0], "color" => "#2a8a9a" },
  # partition walls (blue/green tile), each with a shower head
  *shower_parts.flat_map do |px, pz, w, d|
    tall = 2.4
    [
      { "type" => "box", "size" => [w, tall, d], "pos" => [px, tall / 2.0, pz], "color" => (w > d ? "#3aa08a" : "#2f7fa8") },
      { "type" => "cylinder", "r" => 0.12, "h" => 0.4, "pos" => [px, 2.1, pz], "color" => "#c8ccd0", "segments" => 6 }
    ]
  end,
  # scattered floor drains + a row of shower heads on the back wall
  *[[-2, -2], [2, 1], [0, 4], [-4, 3]].map { |dx, dz| { "type" => "cylinder", "r" => 0.3, "h" => 0.05, "pos" => [dx, 0.03, dz], "color" => "#1a4a52", "segments" => 8 } },
  # steam puffs (pale spheres up high, foreground haze)
  *[[-3, 3.0, 1], [3, 2.6, -2], [0, 2.8, 3], [-1, 2.7, -4]].map { |sx, sy, sz| { "type" => "sphere", "r" => 0.7, "pos" => [sx, sy, sz], "color" => "#dfeff0", "emissive" => "#9ab8ba", "segments" => 6 } }
]

showerworld = {
  "spawn" => { "x" => 0.0, "z" => -5.0, "heading" => 0.0 },
  "background" => "#0a1618",
  "ground_color" => "#1f6f7a",
  "lights" => {
    "ambient" => { "color" => "#8ac0c0", "intensity" => 3.4 },
    "directional" => { "color" => "#d0f0f0", "intensity" => 3.0, "position" => [2, 12, 2] }
  },
  "camera" => { "position" => [10.5, 13, 10.5], "look_at" => [0, 0.3, 0], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 14, blocked: shower_blocked),
  "props" => shower_props,
  "interactables" => [
    { "id" => "shower", "name" => "Shower Head", "x" => -3.0, "z" => -4.0, "radius" => 1.5,
      "text" => "It runs whether or not anyone touches it. The water is\nalways exactly the temperature you were about to want." },
    { "id" => "drain", "name" => "Floor Drain", "x" => 0.0, "z" => 4.0, "radius" => 1.4,
      "text" => "Everything slopes gently toward it. You get the sense the\nwhole labyrinth was built to lead water — and you — here." }
  ],
  "exits" => [
    { "id" => "to_arabic", "to" => "arabic", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 5.4, "heading" => Math::PI } },
    { "id" => "to_university", "to" => "university", "x" => 0.0, "z" => 6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => -5.6, "heading" => 0.0 } }
  ]
}

# ------------------------------------------------ UniversityWorld

uni_blocked = lambda do |cx, cz|
  (cx.abs > 5.0 && cz < -2.0) ||                    # lecture-hall / tower footprints
    (cx.between?(-2.0, 2.0) && cz.between?(-3.5, -1.0)) ||   # central lecture hall
    (Math.hypot(cx - 4.0, cz - 3.5) < 0.4) ||       # flagpole
    ([[-4.5, 2.0], [4.5, 4.0]].any? { |bx, bz| Math.hypot(cx - bx, cz - bz) < 0.7 })  # benches
end

uni_props = [
  *walls(16, 14, color: "#8a7f6a", gaps: [:n], h: 3.0),
  # grass quad
  { "type" => "plane", "size" => [12.0, 8.0], "pos" => [0, 0.01, 2.0], "color" => "#3f7a3c" },
  # central lecture hall (big block, banner, doors)
  { "type" => "box", "size" => [4.4, 3.2, 3.0], "pos" => [0, 1.6, -2.3], "color" => "#b0a488" },
  { "type" => "box", "size" => [4.4, 0.8, 3.2], "pos" => [0, 3.4, -2.3], "color" => "#7a4a3a" },
  { "type" => "box", "size" => [2.6, 1.2, 0.1], "pos" => [0, 2.2, -0.75], "color" => "#c02f4a", "emissive" => "#3a0a12" },
  # two window towers with campus views, back corners
  { "type" => "box", "size" => [3.0, 7.5, 3.0], "pos" => [-6.0, 3.75, -5.0], "color" => "#9a8e78" },
  *window_wall(-6.0, 4.0, -3.5, 2.4, 6.0, rows: 5, cols: 3, color: "#bfe3ff", emissive: "#4a6a88", axis: :z, sign: 1),
  { "type" => "box", "size" => [3.0, 8.5, 3.0], "pos" => [6.0, 4.25, -5.0], "color" => "#948972" },
  *window_wall(6.0, 4.5, -3.5, 2.4, 7.0, rows: 6, cols: 3, color: "#bfe3ff", emissive: "#4a6a88", axis: :z, sign: 1),
  # flagpole
  { "type" => "cylinder", "r" => 0.08, "h" => 4.0, "pos" => [4.0, 2.0, 3.5], "color" => "#cccccc", "segments" => 6 },
  { "type" => "box", "size" => [0.05, 0.7, 1.1], "pos" => [4.05, 3.5, 4.05], "color" => "#2f5ac0", "emissive" => "#12234a" },
  # quad benches
  *[[-4.5, 2.0], [4.5, 4.0]].flat_map do |bx, bz|
    [
      { "type" => "box", "size" => [1.8, 0.16, 0.6], "pos" => [bx, 0.42, bz], "color" => "#6a4f30" },
      { "type" => "box", "size" => [1.8, 0.5, 0.14], "pos" => [bx, 0.7, bz - 0.25], "color" => "#5a4228" }
    ]
  end,
  # a couple of quad trees
  *[[-3.0, 5.0], [3.0, 5.5]].flat_map do |tx, tz|
    [
      { "type" => "cylinder", "r" => 0.2, "h" => 1.4, "pos" => [tx, 0.7, tz], "color" => "#4a3626", "segments" => 6 },
      { "type" => "sphere", "r" => 1.1, "pos" => [tx, 2.0, tz], "color" => "#2e6e36", "segments" => 7 }
    ]
  end,
  # campus notice board
  { "type" => "box", "size" => [1.4, 1.0, 0.1], "pos" => [-4.5, 1.4, 0.6], "color" => "#caa96a" },
  { "type" => "cylinder", "r" => 0.06, "h" => 1.4, "pos" => [-5.1, 0.7, 0.6], "color" => "#4a3626", "segments" => 6 },
  { "type" => "cylinder", "r" => 0.06, "h" => 1.4, "pos" => [-3.9, 0.7, 0.6], "color" => "#4a3626", "segments" => 6 }
]

university = {
  "spawn" => { "x" => 0.0, "z" => 3.0, "heading" => Math::PI },
  "background" => "#243044",
  "ground_color" => "#6a6a58",
  "lights" => {
    "ambient" => { "color" => "#a0a8b8", "intensity" => 3.6 },
    "directional" => { "color" => "#fff0d0", "intensity" => 3.4, "position" => [5, 12, 6] }
  },
  "camera" => { "position" => [11, 12, 12], "look_at" => [0, 0.6, -1.0], "fov" => 48 },
  "walkmesh" => grid_walkmesh(width: 16, depth: 14, blocked: uni_blocked),
  "props" => uni_props,
  "interactables" => [
    { "id" => "hall", "name" => "Lecture Hall", "x" => 0.0, "z" => -1.4, "radius" => 1.7,
      "text" => "Through the doors, a raked room of empty seats and a\nchalkboard mid-proof. The lecture is always about to begin." },
    { "id" => "tower", "name" => "Tower Window", "x" => 6.0, "z" => -3.2, "radius" => 1.7,
      "text" => "Rows of lit windows climb out of sight. From up there,\nthey say, you can see the whole campus and none of the exits." },
    { "id" => "board", "name" => "Campus Board", "x" => -4.5, "z" => 1.3, "radius" => 1.4,
      "kind" => "noteboard",
      "text" => "A corkboard layered with flyers. Anyone may pin a note." }
  ],
  "exits" => [
    { "id" => "to_showerworld", "to" => "showerworld", "x" => 0.0, "z" => -6.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 5.0, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------ The Shanty (garage)

shanty_furniture = [[-4.5, -2.2], [-4.5, 2.2], [4.5, -2.0], [0.0, 2.6]]

shanty_blocked = lambda do |cx, cz|
  (cx.between?(-5.4, -3.4) && cz.between?(-3.2, -1.0)) ||   # couch
    (cx.between?(-5.6, -4.6) && cz.between?(0.8, 3.4)) ||   # bar counter
    (cx.between?(3.6, 5.6) && cz.between?(-3.0, -1.0)) ||   # TV stand
    (Math.hypot(cx, cz - 2.8) < 0.7)                        # coffee table / rug centerpiece
end

shanty_props = [
  *walls(14, 8, color: "#7a746a", gaps: [:e], h: 3.0),
  # windows down the long (south) wall
  *window_wall(0, 1.7, 4.0, 11.0, 1.4, rows: 1, cols: 5, color: "#9ac0d8", emissive: "#3a5a70", axis: :z, sign: -1),
  # flat roof beams + a hanging shop light
  { "type" => "sphere", "r" => 0.25, "pos" => [0, 2.8, 0], "color" => "#fff0c0", "emissive" => "#b09040", "segments" => 8 },
  { "type" => "box", "size" => [0.6, 0.7, 0.4], "pos" => [-4.6, 2.4, -1.0], "color" => "#3a3a3a" },  # roll door mechanism
  # concrete-look rug
  { "type" => "plane", "size" => [5.0, 4.0], "pos" => [-1.0, 0.012, 0.5], "color" => "#4a4038" },
  # couch (L-shaped-ish) facing the TV
  { "type" => "box", "size" => [1.6, 0.5, 2.0], "pos" => [-4.5, 0.25, -2.1], "color" => "#3a5a7a" },
  { "type" => "box", "size" => [0.4, 1.0, 2.0], "pos" => [-5.3, 0.5, -2.1], "color" => "#325070" },
  # TV on a stand + XBox + glow
  { "type" => "box", "size" => [1.8, 0.7, 0.6], "pos" => [4.6, 0.35, -2.0], "color" => "#2a2a2a" },
  { "type" => "box", "size" => [0.15, 1.4, 2.4], "pos" => [5.4, 1.5, -2.0], "color" => "#101014", "emissive" => "#1a3a6a" },
  { "type" => "box", "size" => [0.5, 0.12, 0.5], "pos" => [4.6, 0.78, -2.0], "color" => "#101010", "emissive" => "#0e6a2a" },
  # bar with stools
  { "type" => "box", "size" => [1.0, 1.1, 2.6], "pos" => [-5.1, 0.55, 2.1], "color" => "#4a3626" },
  { "type" => "box", "size" => [1.1, 0.1, 2.8], "pos" => [-5.1, 1.14, 2.1], "color" => "#6a5038" },
  *[1.2, 2.6].map { |sz| { "type" => "cylinder", "r" => 0.2, "h" => 0.7, "pos" => [-3.9, 0.35, sz], "color" => "#2a2a2a", "segments" => 8 } },
  # mini fridge
  { "type" => "box", "size" => [0.9, 1.2, 0.9], "pos" => [-5.0, 0.6, -0.2], "color" => "#c8ccd0" },
  # coffee table with controllers
  { "type" => "box", "size" => [1.4, 0.4, 0.9], "pos" => [0, 0.2, 2.8], "color" => "#3a2e24" }
]

shanty = {
  "spawn" => { "x" => 0.0, "z" => -0.5, "heading" => Math::PI / 2 },
  "background" => "#100e0c",
  "ground_color" => "#5a544a",
  "lights" => {
    "ambient" => { "color" => "#9a8e7a", "intensity" => 3.2 },
    "directional" => { "color" => "#ffe0b0", "intensity" => 2.8, "position" => [-4, 8, 4] }
  },
  "camera" => { "position" => [0, 10, 12.5], "look_at" => [0, 0.6, -0.5], "fov" => 50 },
  "walkmesh" => grid_walkmesh(width: 14, depth: 8, blocked: shanty_blocked),
  "props" => shanty_props,
  "interactables" => [
    { "id" => "xbox", "name" => "The TV & Xbox", "x" => 4.4, "z" => -1.4, "radius" => 1.5,
      "text" => "The disc tray light glows green. Splitscreen is already\ncarved out for four, controllers charged, snacks within reach." },
    { "id" => "couch", "name" => "The Couch", "x" => -3.8, "z" => -2.1, "radius" => 1.5,
      "text" => "Deep, sagging, perfect. There is a permanent Alexander-shaped\ndent on the left cushion. It is warm." },
    { "id" => "bar", "name" => "The Bar", "x" => -3.8, "z" => 2.1, "radius" => 1.5,
      "text" => "A proper corner bar, better stocked than it has any right\nto be. The mini-fridge hums the only music in the room." }
  ],
  "exits" => [
    { "id" => "to_kowloon", "to" => "kowloon", "x" => 6.6, "z" => 0.0, "radius" => 0.9,
      "spawn" => { "x" => -5.4, "z" => 0.0, "heading" => Math::PI / 2 } }
  ]
}

# ------------------------------------------------ The Alley (graffiti wall)

# A dead-end concrete alley off Kowloon. The big north wall is a "canvas" prop:
# a transparent decal plane players spray drawings onto through a pop-up editor
# (see app/javascript/game/ui.js + world.js; drawings persist in the Drawing
# table, keyed by the interactable id "alley_wall").
concrete    = "#6b6660"
concrete_dk = "#4f4b45"

alley_blocked = lambda do |cx, cz|
  (cx.between?(2.6, 4.6) && cz.between?(-4.6, -2.4)) ||   # dumpster
    (cx.between?(-4.4, -3.0) && cz.between?(-3.8, -2.2))  # stacked crates
end

alley_props = [
  # perimeter concrete, open to the south (the alley mouth → Kowloon)
  *walls(10, 12, gaps: [ :s ], h: 4.0, color: concrete),
  # horizontal form-lines on the back wall, just proud of it
  { "type" => "box", "size" => [ 10.0, 0.08, 0.05 ], "pos" => [ 0, 1.2, -5.78 ], "color" => concrete_dk },
  { "type" => "box", "size" => [ 10.0, 0.08, 0.05 ], "pos" => [ 0, 2.9, -5.78 ], "color" => concrete_dk },
  # THE DRAWABLE WALL — transparent decal, painted by players, sits just in
  # front of the north wall's face (z = -5.8) and faces the camera (+z).
  { "type" => "canvas", "id" => "alley_wall", "size" => [ 7.2, 3.0 ], "pos" => [ 0, 2.0, -5.72 ] },
  # dumpster
  { "type" => "box", "size" => [ 1.8, 1.2, 2.0 ], "pos" => [ 3.6, 0.6, -3.5 ], "color" => "#2f6a3a" },
  { "type" => "box", "size" => [ 1.9, 0.2, 2.1 ], "pos" => [ 3.6, 1.25, -3.5 ], "color" => "#264f2c" },
  # stacked crates opposite it
  { "type" => "box", "size" => [ 1.1, 1.0, 1.1 ], "pos" => [ -3.7, 0.5, -3.0 ], "color" => "#6a5030" },
  { "type" => "box", "size" => [ 0.9, 0.9, 0.9 ], "pos" => [ -3.6, 1.45, -3.0 ], "color" => "#5a4228" },
  # drainpipes running the side walls
  { "type" => "cylinder", "r" => 0.12, "h" => 4.0, "pos" => [ -4.7, 2.0, -1.0 ], "color" => "#3a3630", "segments" => 6 },
  { "type" => "cylinder", "r" => 0.12, "h" => 4.0, "pos" => [ 4.7, 2.0, 1.5 ], "color" => "#3a3630", "segments" => 6 },
  # a couple of wall lamps — the light the mural is seen by
  { "type" => "sphere", "r" => 0.18, "pos" => [ -3.0, 3.4, -5.5 ], "color" => "#ffe6a0", "emissive" => "#b0842e", "segments" => 8 },
  { "type" => "sphere", "r" => 0.18, "pos" => [ 3.0, 3.4, -5.5 ], "color" => "#ffe6a0", "emissive" => "#b0842e", "segments" => 8 },
  # neon sign jutting off the east wall
  { "type" => "box", "size" => [ 0.12, 1.1, 1.8 ], "pos" => [ 4.4, 3.0, -0.5 ], "color" => "#ff2f6a", "emissive" => "#ff2f6a" },
  # oily puddle
  { "type" => "plane", "size" => [ 2.4, 1.6 ], "pos" => [ -0.6, 0.012, 1.5 ], "color" => "#23262a", "emissive" => "#0a1418" },
  # trash bags heaped by the dumpster
  { "type" => "sphere", "r" => 0.4, "pos" => [ 2.2, 0.35, -2.6 ], "color" => "#1c1c1c", "segments" => 6 },
  { "type" => "sphere", "r" => 0.35, "pos" => [ 2.6, 0.3, -2.0 ], "color" => "#242424", "segments" => 6 },
  # AC units high on the side walls (foreground occluders)
  { "type" => "box", "size" => [ 0.7, 0.7, 0.6 ], "pos" => [ -4.6, 3.2, 2.5 ], "color" => "#b8b8b8" },
  { "type" => "box", "size" => [ 0.7, 0.7, 0.6 ], "pos" => [ 4.6, 3.6, -2.5 ], "color" => "#a8a8a8" }
]

alley = {
  "spawn" => { "x" => 0.0, "z" => 4.6, "heading" => Math::PI },
  "background" => "#08080a",
  "ground_color" => "#55524c",
  "lights" => {
    "ambient" => { "color" => "#7a7a86", "intensity" => 2.8 },
    "directional" => { "color" => "#c8d0e0", "intensity" => 2.4, "position" => [ 3, 12, 6 ] }
  },
  "camera" => { "position" => [ 1.2, 6.2, 10.5 ], "look_at" => [ 0, 2.0, -5.0 ], "fov" => 46 },
  "walkmesh" => grid_walkmesh(width: 10, depth: 12, blocked: alley_blocked),
  "props" => alley_props,
  "interactables" => [
    { "id" => "alley_wall", "name" => "Concrete Wall", "x" => 0.0, "z" => -3.6, "radius" => 1.9,
      "kind" => "graffiti",
      "text" => "A blank stretch of alley concrete, scarred and painted over\na hundred times. There's a can of spray in your hand." },
    { "id" => "dumpster", "name" => "Dumpster", "x" => 3.6, "z" => -3.2, "radius" => 1.5,
      "text" => "Green, dented, humming with its own ecosystem.\nSomeone has drawn a very good cat on the lid." },
    { "id" => "puddle", "name" => "Oily Puddle", "x" => -0.6, "z" => 1.5, "radius" => 1.4,
      "text" => "A rainbow slick that never dries. Your reflection looks up\nat you and, after a moment, shrugs." }
  ],
  "exits" => [
    { "id" => "to_kowloon", "to" => "kowloon", "x" => 0.0, "z" => 5.6, "radius" => 0.9,
      "spawn" => { "x" => 0.0, "z" => 5.4, "heading" => Math::PI } }
  ]
}

# ------------------------------------------------------------------- persist

[
  { slug: "lounge", name: "The Lounge", data: lounge },
  { slug: "courtyard", name: "The Courtyard", data: courtyard },
  { slug: "arabic", name: "The Sandstone Courtyard", data: arabic },
  { slug: "rainforest", name: "Megalithic Rainforest", data: rainforest },
  { slug: "cenote", name: "The Cenote", data: cenote },
  { slug: "megalith", name: "The Megalithic Complex", data: megalith },
  { slug: "dolmen", name: "Dolmen Viewpoint", data: dolmen },
  { slug: "foodcourt", name: "FoodCourt Ravine", data: foodcourt },
  { slug: "kowloon", name: "Kowloon", data: kowloon },
  { slug: "huaqiangbei", name: "Huaqiangbei Market", data: huaqiangbei },
  { slug: "showerworld", name: "ShowerWorld", data: showerworld },
  { slug: "university", name: "UniversityWorld", data: university },
  { slug: "shanty", name: "The Shanty", data: shanty },
  { slug: "alley", name: "The Alley", data: alley }
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
