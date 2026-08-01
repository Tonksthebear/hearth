Rails.application.routes.draw do
  resource :mcp, only: %i[ show create destroy ]

  namespace :agent do
    resources :conversations, only: %i[ index new create show ] do
      resources :turns, only: :create do
        resource :cancellation, only: :create, controller: "turn/cancellations"
      end
    end
    resources :operational_authorizations, only: %i[ create destroy ]
    resources :mutation_proposals, only: [] do
      resource :decision, only: %i[ create destroy ], controller: :mutation_decisions
    end
  end

  namespace :setup do
    resource :household, only: %i[ new create ]
  end

  resource :session, only: %i[ new create destroy ]
  resources :passwords, param: :token, only: %i[ new create edit update ]
  resources :people, only: %i[ index show new create edit update ]
  resources :recipes, only: %i[ index show new create edit update ]
  resources :ingredients, only: %i[ index edit update ]
  resources :exercises, except: :destroy
  resources :workout_templates, except: :destroy
  resources :training_sessions, only: %i[ new create show edit update destroy ]
  resource :training_week, only: :show
  resource :weekly_dose_target, only: :update
  resource :meal_week, only: :show
  resources :planned_meals, only: %i[ create destroy ] do
    resource :meal, only: :create, module: :planned_meal
  end
  resources :meals, only: %i[ new create show edit update destroy ]
  resource :shopping_list, only: :show do
    resources :items, controller: "shopping_list_items", only: %i[ create edit update destroy ] do
      resource :completion, only: %i[ create destroy ], module: :shopping_list_item
    end
  end
  resource :person_context, only: :update
  resources :habits, only: %i[ index new create edit update ]
  resources :person_habits, only: %i[ create edit update ]
  resource :recovery_day, only: :show
  resources :habit_check_ins, only: %i[ create update destroy ]
  resource :household_week, only: :show
  resource :activity_week, only: :show
  resource :activity_library, only: :show
  resource :activity_history, only: :show
  resources :planned_workouts, only: %i[ create update destroy ] do
    resource :skip, only: %i[ create destroy ], module: :planned_workout
  end

  root "todays#show"

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
