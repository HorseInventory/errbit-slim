class ProblemDecorator < Draper::Decorator
  delegate_all

  def link_text
    object.message.presence || object.error_class
  end

  def notices_count
    notice_statistics.fetch('notices_count')
  end

  def first_notice_at
    notice_statistics.fetch('first_notice_at')&.in_time_zone
  end

  def last_notice_at
    notice_statistics.fetch('last_notice_at')&.in_time_zone
  end

private

  def notice_statistics
    context[:notice_statistics] ||= object.notices.statistics
  end
end
