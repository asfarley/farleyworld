class Room < ApplicationRecord
  has_many :players, dependent: :nullify

  validates :name, :slug, presence: true
  validates :slug, uniqueness: true

  def spawn         = data.fetch("spawn")
  def walkmesh      = data.fetch("walkmesh")
  def interactables = data.fetch("interactables", [])
  def exits         = data.fetch("exits", [])

  # Point-in-walkmesh test on the ground plane (x/z). Used to validate
  # client-reported positions before accepting them.
  def contains?(x, z)
    verts = walkmesh["vertices"]
    walkmesh["triangles"].any? do |(ia, ib, ic)|
      a, b, c = verts[ia], verts[ib], verts[ic]
      point_in_triangle?(x, z, a[0], a[2], b[0], b[2], c[0], c[2])
    end
  end

  def nearest_interactable(x, z)
    interactables
      .map { |i| [i, Math.hypot(i["x"] - x, i["z"] - z)] }
      .select { |i, d| d <= i.fetch("radius", 1.5) }
      .min_by { |_, d| d }
      &.first
  end

  def exit_near(x, z, id)
    exits.find { |e| e["id"] == id && Math.hypot(e["x"] - x, e["z"] - z) <= e.fetch("radius", 1.0) + 0.75 }
  end

  def as_payload
    { "slug" => slug, "name" => name }.merge(data)
  end

  private

  def point_in_triangle?(px, pz, ax, az, bx, bz, cx, cz)
    d1 = sign(px, pz, ax, az, bx, bz)
    d2 = sign(px, pz, bx, bz, cx, cz)
    d3 = sign(px, pz, cx, cz, ax, az)
    has_neg = d1.negative? || d2.negative? || d3.negative?
    has_pos = d1.positive? || d2.positive? || d3.positive?
    !(has_neg && has_pos)
  end

  def sign(px, pz, ax, az, bx, bz)
    (px - bx) * (az - bz) - (ax - bx) * (pz - bz)
  end
end
