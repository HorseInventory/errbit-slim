require 'recurse'

class Notice
  UNAVAILABLE = 'N/A'

  # Mongo will not accept index keys larger than 1,024 bytes and that includes
  # some amount of BSON encoding overhead, so keep it under 1,000 bytes to be
  # safe.
  MESSAGE_LENGTH_LIMIT = 1_000

  include Mongoid::Document
  include Mongoid::Timestamps

  field :message
  field :server_environment, type: Hash
  field :request, type: Hash
  field :notifier, type: Hash
  field :user_attributes, type: Hash
  field :framework
  field :error_class
  field :fingerprint

  belongs_to :problem, inverse_of: :notices
  belongs_to :backtrace, index: true, autosave: true, optional: true

  index(created_at: 1)
  index(problem_id: 1, created_at: 1, _id: 1)
  index(fingerprint: 1)

  before_validation :ensure_fingerprint
  validates :server_environment, :notifier, :fingerprint, presence: true
  before_save :sanitize

  scope :ordered, -> { order_by(:created_at.asc) }
  scope :reverse_ordered, -> { order_by(:created_at.desc) }
  scope :for_problems, lambda { |problems|
    where(:problem_id.in => problems.all.map(&:id))
  }

  # Overwrite the default setter to make sure the message length is no larger
  # than the limit we impose.
  def message=(m)
    truncated_m = m.mb_chars.compose.limit(MESSAGE_LENGTH_LIMIT).to_s
    super(truncated_m)
  end

  def user_agent
    agent_string = env_vars['HTTP_USER_AGENT']
    agent_string.blank? ? nil : UserAgent.parse(agent_string)
  end

  def env_vars
    vars = request['cgi-data']
    vars.is_a?(Hash) ? vars : {}
  end

  def user_agent_string
    if user_agent.nil? || user_agent.none?
      UNAVAILABLE
    else
      "#{user_agent.browser} #{user_agent.version} (#{user_agent.os})"
    end
  end

  def environment
    return 'development' if server_environment.blank?

    n = server_environment['server-environment'] || server_environment['environment-name']
    n.blank? ? 'development' : n
  end

  def component
    request['component']
  end

  def action
    request['action']
  end

  def where
    where = component.to_s.dup
    where << "##{action}" if action.present?
    where
  end

  def request
    super || {}
  end

  def url
    request['url']
  end

  def host
    uri = url && URI.parse(url)
    return uri.host if uri && uri.host.present?

    UNAVAILABLE
  rescue URI::InvalidURIError
    UNAVAILABLE
  end

  def params
    request['params'] || {}
  end

  def session
    request['session'] || {}
  end

  ##
  # TODO: Move on decorator maybe
  #
  def project_root
    server_environment['project-root'] || '' if server_environment
  end

  def app_version
    server_environment['app-version'] || '' if server_environment
  end

  # filter memory addresses out of object strings
  # example: "#<Object:0x007fa2b33d9458>" becomes "#<Object>"
  def filtered_message
    message.gsub(/(#<.+?):[0-9a-f]x[0-9a-f]+(>)/, '\1\2')
  end

  def fingerprint
    value = super
    if value.present?
      value
    else
      self.fingerprint = generate_fingerprint
      super
    end
  end

  delegate :app, to: :problem

  def deduplicated_message
    PatternMatching.deduplicated_message(message)
  end

  def ensure_fingerprint
    self.fingerprint ||= generate_fingerprint
  end

  def backtrace_lines
    backtrace&.lines || []
  end

private

  def generate_fingerprint
    material = []
    material << error_class
    material << filtered_message if message.present?
    material << component
    material << action
    material << environment

    if backtrace
      material << backtrace.lines.first
    end

    Digest::MD5.hexdigest(material.map(&:to_s).join)
  rescue NoMethodError => e
    Rails.logger.error("Error generating fingerprint: #{e.message}")
    nil
  end

  def sanitize
    [:server_environment, :request, :notifier].each do |h|
      send("#{h}=", sanitize_hash(send(h)))
    end
  end

  def sanitize_hash(hash)
    hash.recurse do |recurse_hash|
      recurse_hash.inject({}) do |h, (k, v)|
        if k.is_a?(String)
          h[k.gsub('.', '&#46;').gsub(/^\$/, '&#36;')] = v
        else
          h[k] = v
        end
        h
      end
    end
  end
end
