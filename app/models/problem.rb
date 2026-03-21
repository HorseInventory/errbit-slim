# Represents a single Problem. The problem may have been
# reported as various Errs, but the user has grouped the
# Errs together as belonging to the same problem.

# . At some point we need to break up this class, but I think it doesn't have to be right now.
class Problem
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::Attributes::Dynamic

  field :message
  field :where
  field :environment
  field :error_class
  field :resolved, type: Boolean, default: false
  field :resolved_at, type: Time

  index app_id: 1

  belongs_to :app
  has_many :notices, inverse_of: :problem, dependent: :destroy

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
  scope :ordered_by, ->(sort, order) {
    case sort
    when "environment"    then order_by(["environment", order])
    when "message"        then order_by(["message", order])
    when "created_at"     then ordered
    when "last_notice_at", "count" then all # Sorted by ProblemAggregationSorter (DB aggregation)
    else fail("\"#{sort}\" is not a recognized sort")
    end
  }

  scope :filtered, ->(filter) {
    return all if filter.blank?

    app_names_to_exclude = filter.scan(/-app:(["'])(.+?)\1|-app:([^\s]+)/).map { |q1, q2, noq| q2 || noq }.compact
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

  def app_name
    app&.name
  end

  delegate :count, to: :notices, prefix: true

  def first_notice_at
    notices.ordered.first&.created_at
  end

  def last_notice_at
    notices.reverse_ordered.first&.created_at
  end
end
