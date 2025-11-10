# encoding: utf-8
module SortHelper
  def link_for_sort(name, field = nil)
    field ||= name.underscore
    current = (params_sort == field)
    order = if current && params_order == "desc"
      # Opposite of current order
      "asc"
    elsif current && params_order == "asc"
      # Opposite of current order
      "desc"
    elsif field == "message" || field == "app" || field == "environment"
      # Alphabetical order
      "asc"
    elsif field == "last_notice_at"
      # Date order - Most recent first
      "desc"
    elsif field == "count"
      # Count order - Most frequent first
      "desc"
    else
      # Default order - Alphabetical / numeric order
      "asc"
    end
    url = request.path + "?sort=#{field}&order=#{order}"
    url += "&all_errs=true" if all_errs
    options = {}
    options[:class] = "current #{order}" if current
    link_to(name, url, options)
  end
end
