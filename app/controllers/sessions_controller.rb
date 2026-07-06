class SessionsController < ApplicationController
  def new
    # Dev convenience: /?as=Name logs in without the form (handy for testing
    # multiple players in different browsers).
    if Rails.env.development? && params[:as].present?
      player = Player.enter!(params[:as].to_s.strip.first(20))
      if (room = Room.find_by(slug: params[:room]))
        spawn = room.spawn
        player.update!(room:, x: spawn["x"], z: spawn["z"], heading: spawn.fetch("heading", 0.0))
      end
      sign_in(player, preview: params[:preview], touch: params[:touch])
      return
    end

    redirect_to play_path if current_player
  end

  def create
    name = params[:name].to_s.strip
    if name.blank?
      redirect_to root_path, alert: "Enter a name first."
      return
    end

    sign_in(Player.enter!(name.first(20)))
  end

  def destroy
    cookies.delete(:player_id)
    redirect_to root_path
  end

  private

  def sign_in(player, preview: nil, touch: nil)
    cookies.signed[:player_id] = { value: player.id, httponly: true, same_site: :lax }
    redirect_to play_path(preview: preview.presence, touch: touch.presence)
  end
end
