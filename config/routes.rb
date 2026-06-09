Rails.application.routes.draw do
  post "files", to: "tus_files#create"
  post "files/", to: "tus_files#create"
  patch "files/:id", to: "tus_files#update"
  match "files/:id", to: "tus_files#show", via: :head
  options "files", to: "tus_files#options"
  options "files/:id", to: "tus_files#options"

  post "api/dataset/:dataset_key/datafile", to: "api_dataset#datafile", defaults: { format: :json }

  # Auth
  match "/auth/failure", to: "sessions#unauthorized", as: :unauthorized, via: %i[get post]
  match "/auth/:provider/callback", to: "sessions#create", via: %i[get post]
  match "/login", to: "sessions#new", as: :login, via: %i[get post]
  match "/logout", to: "sessions#destroy", as: :logout, via: %i[get post delete]
  match "/auth/:provider", to: "sessions#new", via: %i[get post]
  post  "role_switch", to: "sessions#role_switch"

  # Core dataset resources
  resources :datasets do
    collection do
      get :pre_deposit
    end

    member do
      get :pre_version
      get :version_controls
      get :download_metrics, defaults: { format: :json }
      get :record_text
      get :confirm_review
      get :get_current_token, defaults: { format: :json }
      get :get_new_token, defaults: { format: :json }
      post :request_review
      post :submit_version_request
      get :version_acknowledge
      get :download_link, defaults: { format: :json }
      post :copy_version_files
      post "approve_version_request/:version_request_id", action: :approve_version_request, as: :approve_version_request
      post "reject_version_request/:version_request_id", action: :reject_version_request, as: :reject_version_request
      post :publish
      post :replay_failed_deliveries
    end
    resources :datafiles, param: :web_id, except: %i[index new show] do
      member { get :download }
    end
    resources :dataset_access_grants, only: %i[create destroy]
    resources :creators,          except: %i[index new show] do
      collection do
        get :orcid_lookup
      end
    end
    resources :contributors,      except: %i[index new show]
    resources :funders,           except: %i[index new show]
    resources :notes
    resources :related_materials, except: %i[index new show]
  end

  post "datasets/:id/version", to: "datasets#create_version", as: :version_dataset

  get "admin", to: "welcome#admin", as: :admin
  post "admin/clear_cache", to: "welcome#clear_cache", as: :clear_admin_cache
  patch "admin/update_system_message", to: "welcome#update_system_message", as: :update_admin_system_message
  post "admin/managed_curators", to: "welcome#create_managed_curator", as: :admin_managed_curators
  delete "admin/managed_curators/:id", to: "welcome#destroy_managed_curator", as: :admin_managed_curator
  post "admin/managed_deposit_exceptions", to: "welcome#create_managed_deposit_exception", as: :admin_managed_deposit_exceptions
  delete "admin/managed_deposit_exceptions/:id", to: "welcome#destroy_managed_deposit_exception", as: :admin_managed_deposit_exception

  get "admin/external_delivery_attempts", to: "external_delivery_attempts#index", as: :admin_external_delivery_attempts
  post "admin/external_delivery_attempts/:id/replay", to: "external_delivery_attempts#replay", as: :replay_admin_external_delivery_attempt
  post "admin/external_delivery_attempts/replay_selected", to: "external_delivery_attempts#replay_selected", as: :replay_selected_admin_external_delivery_attempts
  post "admin/ingest_response_events/:id/acknowledge", to: "external_delivery_attempts#acknowledge_orphan_response", as: :acknowledge_admin_ingest_response_event

  namespace :guide do
    resources :sections, except: :show
    resources :items, except: :show
    resources :subitems, except: :show
  end

  resources :featured_researchers do
    member do
      get :preview
    end
  end
  get "/researcher_spotlights", to: "featured_researchers#index", as: :researcher_spotlights

  resources :curator_reports, only: %i[index show destroy] do
    member do
      get :download
    end

    collection do
      post :request_file_audit
    end
  end

  get "/metric", to: "metrics#index"
  get "/admin_metrics", to: "metrics#admin_metrics"
  resources :metrics, only: :index do
    collection do
      get :archived_content_csv
      get :datafiles_csv
      get :datafiles_simple_list
      get :dataset_downloads, defaults: { format: :json }
      get :file_downloads, defaults: { format: :json }
      get :funders_csv
      get :refresh_dataset_downloads
      get :refresh_datafile_downloads
      get :refresh_datafiles_csv
      get :refresh_container_csv
      get :related_materials_csv
      get :refresh_datasets_tsv
      get :refresh_funders_csv
      get :refresh_related_materials_csv
      get :refresh_container_contents_csv
    end
  end

  # Static / nav pages
  get "/button_examples", to: "welcome#button_examples", as: :button_examples
  get "/badge_examples", to: "welcome#badge_examples", as: :badge_examples
  get "/curator_guide", to: "welcome#curator_guide", as: :curator_guide
  get "/illinois_experts", to: "illinois_experts#index", defaults: { format: :xml }, as: :illinois_experts
  get "/illinois_experts/persons", to: "illinois_experts#persons", defaults: { format: :xml }, as: :illinois_experts_persons
  get "/illinois_experts/example", to: "illinois_experts#example", defaults: { format: :xml }, as: :illinois_experts_example
  get "/deposit",  to: redirect("/datasets/pre_deposit"), as: :deposit
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
