class Player < ApplicationRecord
  belongs_to :room

  validates :name, presence: true, length: { maximum: 20 }

  ACTIVE_WINDOW = 5.minutes

  scope :active, -> { where(last_seen_at: ACTIVE_WINDOW.ago..) }

  def self.enter!(name)
    room = Room.find_by!(slug: "lounge")
    spawn = room.spawn
    create!(
      name: name.strip,
      room: room,
      x: spawn["x"], z: spawn["z"],
      heading: spawn.fetch("heading", 0.0),
      last_seen_at: Time.current
    )
  end

  def as_state
    { "id" => id, "name" => name, "x" => x, "z" => z, "heading" => heading }
  end
end
