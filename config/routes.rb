Rails.application.routes.draw do
  root "documents#index"

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  get "ess/login", to: "sessions#ess_login", as: :ess_login
  get "ess/login/:employee_code", to: "sessions#ess_login", as: :signed_ess_login
  get "users/sign_in/:employee_code", to: "sessions#ess_login", as: :external_employee_sign_in
  delete "logout", to: "sessions#destroy"
  resource :profile, only: %i[edit update]

  resources :documents, only: %i[index show destroy] do
    collection do
      post :request_folder_otp
      get :verify_folder
      post :confirm_folder_otp
      get :download_folder
    end

    member do
      post :request_otp
      get :verify
      post :confirm_otp
      get :download
    end
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
