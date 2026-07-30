require Rails.root.join("lib/tailwindplus_elements_components/form_builder")
require Rails.root.join("lib/tailwindplus_elements_components/tag_helper")

ActiveSupport.on_load(:action_view) do
  include TailwindplusElementsComponents::TagHelper
end

ActionView::Base.default_form_builder = TailwindplusElementsComponents::FormBuilder

ActionView::Base.field_error_proc = proc do |html_tag, instance|
  if html_tag.include?("<label")
    html_tag
  else
    tagged = if html_tag.include?('aria-invalid="true"')
      html_tag
    else
      html_tag.sub(/(?=\/?>)/, ' aria-invalid="true"')
    end

    error = Array(instance.error_message).first
    next tagged unless error

    safe_error = ERB::Util.html_escape(error)
    "#{tagged}<p class=\"mt-2 text-sm text-danger-600 dark:text-danger-400\">#{safe_error}</p>".html_safe
  end
end
