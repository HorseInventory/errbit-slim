class ProblemDecorator < Draper::Decorator
  decorates_association :notices
  delegate_all

  def link_text
    object.message.presence || object.error_class
  end

  # When present (Problem list after aggregation), avoids N+1 queries on notices.
  def notices_count
    if context.key?(:notices_count)
      context[:notices_count]
    else
      object.notices_count
    end
  end

  def last_notice_at
    if context.key?(:last_notice_at)
      context[:last_notice_at]
    else
      object.last_notice_at
    end
  end
end
