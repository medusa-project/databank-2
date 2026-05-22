Rails.application.routes.draw do
  # Auth
  get "login",  to: "sessions#new",     as: :login
  delete "logout", to: "sessions#destroy", as: :logout
  post  "role_switch", to: "sessions#role_switch"
  match "/auth/:provider/callback", to: "sessions#create", via: %i[get post]

  # Core dataset resources
  resources :datasets do
    member do
      get :pre_version
      get :version_controls
      post :submit_version_request
      get :version_acknowledge
      post :copy_version_files
      post "approve_version_request/:version_request_id", action: :approve_version_request, as: :approve_version_request
      post "reject_version_request/:version_request_id", action: :reject_version_request, as: :reject_version_request
      post :publish
      post :replay_failed_deliveries
    end
    resources :datafiles, param: :web_id, except: %i[index new show] do
      member { get :download }
    end
    resources :creators,          except: %i[index new show]
    resources :contributors,      except: %i[index new show]
    resources :funders,           except: %i[index new show]
    resources :related_materials, except: %i[index new show]
  end

  post "datasets/:id/version", to: "datasets#create_version", as: :version_dataset

  get "admin/external_delivery_attempts", to: "external_delivery_attempts#index", as: :admin_external_delivery_attempts
  post "admin/external_delivery_attempts/:id/replay", to: "external_delivery_attempts#replay", as: :replay_admin_external_delivery_attempt
  post "admin/external_delivery_attempts/replay_selected", to: "external_delivery_attempts#replay_selected", as: :replay_selected_admin_external_delivery_attempts

  # Static / placeholder nav pages
  get "/deposit",  to: "pages#deposit",  as: :deposit
  get "/policies", to: "pages#policies", as: :policies
  get "/guides",   to: "pages#guides",   as: :guides
  get "/contact",  to: "pages#contact",  as: :contact

  # Errors
  post "/", to: "errors#error404"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Route unmatched HTML requests through app layout so shared nav/header renders.
  match "*unmatched", to: "errors#error404", via: :all, constraints: ->(req) { req.format.html? }

  root "welcome#index"
end
