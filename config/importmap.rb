# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "@tailwindplus/elements", to: "@tailwindplus--elements.js" # @1.0.22
pin "tailwindplus_elements_components", to: "tailwindplus_elements_components.js"
