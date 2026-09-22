class BacktraceLineDecorator < Draper::Decorator
  EMPTY_STRING = ''.freeze

  def in_app?
    return false if file.blank?
    file.match Backtrace::IN_APP_PATH
  end

  def number
    object[:number]
  end

  def column
    object[:column]
  end

  def file
    object.try(:[], :file).to_s
  end

  def method
    object[:method]
  end

  def file_relative
    file.to_s.sub(Backtrace::IN_APP_PATH, EMPTY_STRING)
  end

  def file_name
    File.basename file
  end

  def to_s
    column = object.try(:[], :column)
    "#{file_relative}:#{number}#{column.present? ? ":#{column}" : ''}"
  end

  def link_to_source_file(app, &block)
    text = h.capture_haml(&block)
    link_to_in_app_source_file(app, text) || text
  end

  def path
    return '' if file.blank?
    File.dirname(file).gsub(/^\.$/, '') + "/"
  end

  def decorated_path
    path.
      sub(Backtrace::IN_APP_PATH, '').
      sub(Backtrace::GEMS_PATH, "<strong>\\1</strong>")
  end

private

  def link_to_in_app_source_file(app, text)
    return unless in_app?
    if file_name =~ /\.js$/
      link_to_hosted_javascript(app, text)
    else
      link_to_custom_backtrace_url(app, text)
    end
  end

  def link_to_hosted_javascript(app, text)
    return unless app.asset_host?
    h.link_to(text, "#{app.asset_host}/#{file_relative}", target: '_blank')
  end

  def link_to_custom_backtrace_url(app, text)
    return unless app.custom_backtrace_url_template?
    href = app.custom_backtrace_url(decorated_path + file_name, number)
    h.link_to(text, href, target: '_blank')
  end
end
