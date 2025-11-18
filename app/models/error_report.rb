include PatternMatching

##
# Processes a new error report.
#
# Accepts a hash with the following attributes:
#
# * <tt>:error_class</tt> - the class of error
# * <tt>:message</tt> - the error message
# * <tt>:backtrace</tt> - an array of stack trace lines
#
# * <tt>:request</tt> - a hash of values describing the request
# * <tt>:server_environment</tt> - a hash of values describing the server environment
#
# * <tt>:notifier</tt> - information to identify the source of the error report
#
class ErrorReport
  MAX_RECENT_NOTICES = 100

  attr_reader :app

  attr_reader :notice
  attr_reader :problem

  def initialize(attributes)
    attributes.with_indifferent_access.each do |k, v|
      instance_variable_set(:"@#{k}", v)
    end
    @app ||= App.where(api_key: api_key).first
  end

  def valid?
    return false if @app.nil?

    @notice ||= make_notice
    @notice.valid?
  end

  def generate_notice!
    @notice ||= make_notice

    if @problem.resolved?
      @problem.unresolve
    end

    @problem.save!
    @notice.save!

    compress_old_notices

    email_notification
    @notice
  end

  def errors
    if @app.nil?
      return "Invalid api_key: #{api_key}"
    end

    @notice.errors.full_messages + @problem.errors.full_messages
  end

  def make_notice
    @notice = new_notice
    @problem ||= select_or_create_problem(@notice)
    @problem.app = @app
    @notice.problem = @problem
    @notice.ensure_fingerprint
    @notice
  end

  def select_or_create_problem(notice)
    similar_problems = find_similar_problems(notice).to_a

    if similar_problems.empty?
      @app.find_or_build_problem(notice)
    elsif similar_problems.size > 2
      ProblemMerge.new(similar_problems).merge
    else
      similar_problems.first
    end
  end

  def new_notice
    @notice ||= Notice.new(
      backtrace:          backtrace.blank? ? nil : Backtrace.find_or_build(backtrace),
      error_class:        error_class,
      framework:          framework,
      message:            message,
      notifier:           notifier,
      request:            request,
      server_environment: server_environment,
      user_attributes:    user_attributes,
    )
  end

  def email_notification
    return unless should_email?

    Mailer.err_notification(self).deliver_now
  end

  def should_email?
    @should_email ||= app.emailable? && app.notification_recipients.any? &&
      (app.email_at_notices.include?(0) ||
      app.email_at_notices.include?(notices_count))
  end

  def find_similar_problems(notice)
    problem_ids = Notice.where(
      message: /\A#{PatternMatching.text_to_regex_string(notice.message)}\z/i,
    ).pluck(:problem_id)

    return [] if problem_ids.empty?

    Problem.where(
      app_id: app.id,
      :_id.in => problem_ids,
    ).order(created_at: :asc)
  end

private

  # Our DB size is limited, so we need to compress / trim old notices to keep the DB size down.
  # Basically just delete a bunch of the extra likely-duplicate notices and backtraces
  def compress_old_notices
    if notices_count > MAX_RECENT_NOTICES
      # Get notices to keep (MAX_RECENT_NOTICES most recent)
      notices_to_delete = problem.notices.reverse_ordered.skip(MAX_RECENT_NOTICES).only(:id, :backtrace_id)
      notice_ids_to_delete = notices_to_delete.pluck(:id)

      # "compress" notices not in our keep list
      problem.notices.where(:id.in => notice_ids_to_delete).update_all(
        server_environment: {},
        request: nil,
        notifier: {},
        user_attributes: nil,
        framework: nil,
        error_class: nil,
      )

      # And delete backtraces
      backtrace_ids_to_delete = notices_to_delete.pluck(:backtrace_id)
      Backtrace.where(:id.in => backtrace_ids_to_delete).delete_all

      notices_count - MAX_RECENT_NOTICES
    else
      0
    end
  end

  def notices_count
    @notices_count ||= problem.notices_count
  end

  attr_reader :api_key

  attr_reader :backtrace
  attr_reader :error_class
  attr_reader :framework
  attr_reader :message
  attr_reader :notifier
  attr_reader :request
  attr_reader :server_environment
  attr_reader :user_attributes
end
