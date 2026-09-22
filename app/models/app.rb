class App
  include Comparable
  include Mongoid::Document
  include Mongoid::Timestamps

  field :name, type: String
  field :api_key
  field :custom_backtrace_url_template
  field :asset_host
  field :repository_branch
  field :current_app_version
  field :notify_on_errs, type: Boolean, default: true
  field :email_at_notices, type: Array, default: Errbit::Config.email_at_notices

  field :_id,
    type:          String,
    pre_processed: true,
    default:       -> { BSON::ObjectId.new.to_s }

  has_many :problems, inverse_of: :app, dependent: :destroy

  before_validation :generate_api_key, on: :create

  validates :name, :api_key, presence: true, uniqueness: { allow_blank: true }

  index({ name: "text" }, default_language: "english")

  scope :search, ->(value) { where('$text' => { '$search' => value }) }

  def find_or_build_problem(unsaved_notice)
    existing_notice = Notice.where(
      fingerprint: unsaved_notice.fingerprint,
    ).first
    return existing_notice.problem if existing_notice

    problems.build(
      message: unsaved_notice.deduplicated_message,
      where: unsaved_notice.where,
      environment: unsaved_notice.environment,
      error_class: unsaved_notice.error_class,
    )
  end

  def emailable?
    notify_on_errs
  end

  def repo_branch
    repository_branch.present? ? repository_branch : 'master'
  end

  # Provide decorator-compatible helpers
  def custom_backtrace_url_template?
    custom_backtrace_url_template.present?
  end

  def custom_backtrace_url(file, line)
    return unless custom_backtrace_url_template?

    format(
      custom_backtrace_url_template,
      branch: repo_branch,
      file: file,
      line: line,
      ebranch: CGI.escape(repo_branch),
      efile: CGI.escape(file),
    )
  end

  def notification_recipients
    @notification_recipients ||= User.all.map(&:email).reject(&:blank?)
  end

  # Copy app attributes from another app.
  def copy_attributes_from(app_id)
    copy_app = App.where(_id: app_id).first
    return if copy_app.blank?

    # Copy fields
    (copy_app.fields.keys - ['_id', 'name', 'created_at', 'updated_at']).each do |k|
      send("#{k}=", copy_app.send(k))
    end
  end

  def unresolved_count
    @unresolved_count ||= problems.unresolved.count
  end

  def problem_count
    @problem_count ||= problems.count
  end

  # Compare by number of unresolved errs, then problem counts.
  def <=>(other)
    (other.unresolved_count <=> unresolved_count).nonzero? ||
      (other.problem_count <=> problem_count).nonzero? ||
      name <=> other.name
  end

  def email_at_notices
    Errbit::Config.per_app_email_at_notices ? super : Errbit::Config.email_at_notices
  end

  def regenerate_api_key!
    update_attribute(:api_key, SecureRandom.hex)
  end

private

  def generate_api_key
    self.api_key ||= SecureRandom.hex
  end
end
