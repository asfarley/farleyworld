module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_player

    def connect
      self.current_player = find_player || reject_unauthorized_connection
    end

    private

    def find_player
      Player.find_by(id: cookies.signed[:player_id])
    end
  end
end
