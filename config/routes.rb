Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get 'test_auth' => 'application#test_auth'
  mount ActionCable.server => '/cable'
  
  # Auth
  post '/signin', to: 'signin#create'
  delete '/signout', to: 'signin#destroy'

  resources :states, only: [:index]
  resources :form_submissions, only: [:create]
  
  resources :reports, only: [:index] do
    collection do
      post :refresh
    end
  end

  resources :livestock_summaries, only: [:index], path: 'livestock_summaries'

  namespace :api do
      
    end

  # Minimal documents endpoint placeholder for health
  get '/api/health', to: proc { [200, { 'Content-Type' => 'application/json' }, [{ status: 'healthy' }.to_json]] }

end
