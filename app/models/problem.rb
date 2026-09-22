class Problem
  include Mongoid::Document
  include Mongoid::Timestamps

  field :message
  field :where
  field :environment
  field :error_class
  field :resolved, type: Boolean, default: false
  field :resolved_at, type: Time

  index app_id: 1

  belongs_to :app
  has_many :notices, inverse_of: :problem, dependent: :delete_all

  around_destroy :remove_unreferenced_backtraces

  scope :resolved, -> { where(resolved: true) }
  scope :unresolved, -> { where(resolved: false) }
  scope :ordered, -> { order_by(:created_at.desc) }
  scope :for_apps, ->(apps) {
    if apps.selector.empty?
      all
    else
      where(:app_id.in => apps.map(&:id))
    end
  }
  scope :all_else_unresolved, ->(fetch_all) { fetch_all ? all : where(resolved: false) }
  scope :in_env, ->(environment) { environment.blank? ? all : where(environment: environment) }
  scope :filtered, ->(filter) {
    return all if filter.blank?

    app_names_to_exclude = filter.scan(/-app:(["'])(.+?)\1|-app:([^\s]+)/).map { |_quote, quoted_name, unquoted_name| quoted_name || unquoted_name }.compact
    return all if app_names_to_exclude.blank?

    excluded_ids = App.where(:name.in => app_names_to_exclude).pluck(:id)
    where(:app_id.nin => excluded_ids)
  }

  # looking up the Notice inside the scope is a hack, but it's handy to have
  # the scope for chaining. i'm assuming that the indexed Notice lookup is not
  # costly (it is not for me with 10,000,000 notices), especially with how
  # infrequently searches happen
  scope :search, lambda { |value|
    value = value.to_s.strip
    if (value.start_with?('"') && value.end_with?('"')) || (value.start_with?("'") && value.end_with?("'"))
      value = value[1..-2]
    end
    notice = Notice.where(id: value).first
    if notice
      where(id: notice.problem_id)
    else
      problem_ids_from_notices = Notice.any_of(
        { message: /#{Regexp.escape(value)}/i },
        { error_class: /#{Regexp.escape(value)}/i },
        { 'request.component' => /#{Regexp.escape(value)}/i },
      ).distinct(:problem_id)
      # Also match legacy cached fields on Problem if present
      cached_match = any_of(
        { message: /#{Regexp.escape(value)}/i },
        { error_class: /#{Regexp.escape(value)}/i },
        { where: /#{Regexp.escape(value)}/i },
      ).pluck(:id)
      where(:_id.in => (problem_ids_from_notices + cached_match).uniq)
    end
  }

  def url
    Rails.application.routes.url_helpers.app_problem_url(
      app,
      self,
      protocol: Errbit::Config.protocol,
      host:     Errbit::Config.host,
      port:     Errbit::Config.port,
    )
  end

  def resolve!
    self.update!(resolved: true, resolved_at: Time.zone.now)

    latest_id = notices.reverse_ordered.pick(:id)
    NoticeDestroy.new(notices.where(:id.ne => latest_id)).execute

    true
  end

  def unresolve
    self.resolved = false
    self.resolved_at = nil
  end

  def unresolve!
    self.update!(resolved: false, resolved_at: nil)
  end

  def unresolved?
    !resolved?
  end

  delegate :count, to: :notices, prefix: true

  def compress_notices
    old_notices = notices.uncompressed.reverse_ordered.skip(Notice::MAX_RECENT_NOTICES)
    rows = old_notices.pluck(:id, :backtrace_id)
    return if rows.empty?

    notices.where(:id.in => rows.map(&:first)).update_all(
      compressed: true,
      server_environment: {},
      request: nil,
      notifier: {},
      user_attributes: nil,
      framework: nil,
      error_class: nil,
      backtrace_id: nil,
    )
    Backtrace.delete_unreferenced(rows.map(&:last).compact.uniq)
  end

  def first_notice_at
    notices.ordered.pick(:created_at)
  end

  def last_notice_at
    notices.reverse_ordered.pick(:created_at)
  end

private

  def remove_unreferenced_backtraces
    backtrace_ids = notices.distinct(:backtrace_id).compact
    yield
    Backtrace.delete_unreferenced(backtrace_ids)
  end
end
