class AppDecorator < Draper::Decorator
  delegate_all

  def email_at_notices
    (object.email_at_notices || []).join(', ')
  end

  def notify_err_display
    object.notify_on_errs ? '' : 'display: none;'
  end
end
