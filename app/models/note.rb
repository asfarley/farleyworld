# A player-written note pinned to a "noteboard" interactable in some room.
# User content, so it lives in its own table rather than Room#data (which is
# regenerated from seeds). `board_id` matches the interactable's id, letting a
# room hold more than one board.
class Note < ApplicationRecord
  belongs_to :room

  MAX_BODY = 140  # characters; keep notes short and postcard-like
  KEEP = 40       # newest notes shown per board

  validates :board_id, :author, presence: true
  validates :body, presence: true, length: { maximum: MAX_BODY }

  scope :for_board, ->(room, board_id) { where(room: room, board_id: board_id) }
  scope :recent, -> { order(created_at: :desc) }

  def to_payload
    { "id" => id, "author" => author, "body" => body, "at" => created_at.to_i }
  end
end
