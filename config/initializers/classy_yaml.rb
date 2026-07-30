Classy::Yaml.setup do |config|
  config.default_file = Rails.root.join("config/elements.yml")
  config.override_tag_helpers = true
end
