Rails.application.routes.draw do
  devise_for :users

  resources :users

  resources :problems, only: [:index] do
    collection do
      post :destroy_several
      post :resolve_several
      post :unresolve_several
      post :merge_several
      get :search
    end
    resources :notices, only: [:index]
  end
  get 'problems/:id' => 'problems#show_by_id', as: :problem

  resources :apps do
    resources :problems, only: [:index, :show, :destroy] do
      collection do
        post :destroy_all
      end

      member do
        put :resolve
      end
    end

    member do
      post :regenerate_api_key
    end
    collection do
      get :search
    end
  end

  get 'health/readiness' => 'health#readiness'
  get 'health/liveness' => 'health#liveness'
  get 'health/api-key-tester' => 'health#api_key_tester'

  match '/api/v3/projects/:project_id/create-notice' => 'api/v3/notices#create', via: [:post]
  match '/api/v3/projects/:project_id/notices' => 'api/v3/notices#create', via: [:post, :options]

  root to: 'apps#index'
end
