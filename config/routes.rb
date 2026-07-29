Rails.application.routes.draw do
  namespace :setup do
    resource :household, only: %i[ new create ]
  end

  resource :session, only: %i[ new create destroy ]
  resources :passwords, param: :token, only: %i[ new create edit update ]
  resources :people, only: %i[ index new create edit update ]
  resources :recipes, only: %i[ index show new create edit update ]
  resources :exercises, except: :destroy
  resources :workout_templates, except: :destroy
  resources :training_sessions, only: %i[ new create show edit update destroy ]
  resource :training_week, only: :show
  resource :weekly_dose_target, only: :update
  resource :meal_week, only: :show
  resources :planned_meals, only: %i[ create destroy ]
  resources :meal_logs, only: %i[ create destroy ]
  resource :shopping_list, only: :show
  resource :person_context, only: :update

  root "dashboard#show"

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
