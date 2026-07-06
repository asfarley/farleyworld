Rails.application.routes.draw do
  root "sessions#new"
  resource :session, only: [ :create, :destroy ]

  get "play" => "game#show", as: :play
  get "rooms/:slug" => "rooms#show", as: :room, defaults: { format: :json }

  get "up" => "rails/health#show", as: :rails_health_check
end
