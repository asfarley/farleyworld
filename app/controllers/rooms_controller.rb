class RoomsController < ApplicationController
  def show
    return head :unauthorized unless current_player

    room = Room.find_by!(slug: params[:slug])
    render json: room.as_payload
  end
end
