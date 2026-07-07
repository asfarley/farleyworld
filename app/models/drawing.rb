# A player's drawing sprayed onto a "graffiti" wall in some room. Like Note,
# it's user content, so it lives in its own table rather than Room#data (which
# is regenerated from seeds). `wall_id` matches the interactable's id, so a room
# can hold more than one drawable wall. The wall shows the most recent drawing;
# each submission starts from the current one (the editor preloads it), so the
# wall accretes into a shared mural. Older versions are kept briefly as history.
class Drawing < ApplicationRecord
  belongs_to :room

  KEEP = 12            # versions retained per wall (newest is the live one)
  MAX_BYTES = 320_000  # ~240KB of PNG once base64-decoded; plenty for 512×320

  # A transparent PNG, transported as a data: URL. Nothing else is accepted, so
  # the string can be dropped straight into an <img>/texture without sanitizing.
  DATA_URL = %r{\Adata:image/png;base64,[A-Za-z0-9+/\r\n=]+\z}

  validates :wall_id, :author, :image, presence: true
  validate  :image_is_png_data_url

  scope :for_wall, ->(room, wall_id) { where(room: room, wall_id: wall_id) }
  scope :recent, -> { order(created_at: :desc) }

  def self.valid_image?(str)
    str.is_a?(String) && str.bytesize <= MAX_BYTES && str.match?(DATA_URL)
  end

  # Trim a wall's history down to the newest KEEP versions.
  def self.prune(room, wall_id)
    stale = for_wall(room, wall_id).recent.offset(KEEP).pluck(:id)
    where(id: stale).delete_all if stale.any?
  end

  def to_payload
    { "wall" => wall_id, "image" => image, "author" => author, "at" => created_at.to_i }
  end

  private

  def image_is_png_data_url
    return if self.class.valid_image?(image)

    errors.add(:image, "must be a PNG data URL under #{MAX_BYTES} bytes")
  end
end
