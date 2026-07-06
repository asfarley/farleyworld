class GameController < ApplicationController
  def show
    redirect_to root_path unless current_player
  end
end
