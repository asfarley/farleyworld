# A Dark Souls-style message a player leaves on the ground for others to find:
# a glowing glyph at the writer's position plus a short cryptic line you read by
# examining it. Like Note/Drawing it's user content, so it lives in its own
# table rather than Room#data (which is regenerated from seeds). Every message in
# a room is public — drawn on the floor wherever it was left.
class Soapstone < ApplicationRecord
  belongs_to :room

  MAX_BODY = 100  # characters; a single cryptic line, like the real thing
  KEEP = 60       # newest messages kept per room; the oldest fade away

  # The sigil stamped on the ground. The client sends one of these exact glyphs
  # and renders the same character, so this set is the whole contract.
  GLYPHS = %w[✦ ➤ ◆ ✕ ✚ ☉ ♥ ✷].freeze

  validates :author, presence: true
  validates :body, presence: true, length: { maximum: MAX_BODY }
  validates :glyph, inclusion: { in: GLYPHS }

  scope :for_room, ->(room) { where(room: room) }
  scope :recent, -> { order(created_at: :desc) }

  # Trim a room down to its newest KEEP messages.
  def self.prune(room)
    stale = for_room(room).recent.offset(KEEP).pluck(:id)
    where(id: stale).delete_all if stale.any?
  end

  def to_payload
    { "id" => id, "x" => x, "z" => z, "heading" => heading,
      "glyph" => glyph, "body" => body, "author" => author, "at" => created_at.to_i }
  end
end
