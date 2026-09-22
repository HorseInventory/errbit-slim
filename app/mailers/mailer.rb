class Mailer < ActionMailer::Base
  default :from                      => Errbit::Config.email_from,
    'X-Errbit-Host'            => Errbit::Config.host,
    'X-Mailer'                 => 'Errbit',
    'X-Auto-Response-Suppress' => 'OOF, AutoReply',
    'Precedence'               => 'bulk',
    'Auto-Submitted'           => 'auto-generated'

  def err_notification(error_report)
    @notice   = NoticeDecorator.new(error_report.notice)
    @app      = AppDecorator.new(error_report.app)

    errbit_headers(
      'App'         => @app.name,
      'Environment' => @notice.environment,
      'Notice-Id'   => @notice.id,
    )

    mail(
      to:      @app.notification_recipients,
      subject: @notice.message.truncate(50),
    )
  end

private

  def errbit_headers(header)
    header.each { |key, value| headers["X-Errbit-#{key}"] = value.to_s }
  end
end
