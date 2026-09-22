class Backtrace
  include Mongoid::Document
  include Mongoid::Timestamps

  IN_APP_PATH = %r{^(?:\[|/)PROJECT_ROOT\]?(?!(/vendor))/?}
  GEMS_PATH = %r{(?:\[|/)GEM_ROOT\]?/gems/([^/]+)}

  field :fingerprint
  field :lines

  index fingerprint: 1

  before_validation :ensure_fingerprint
  validates :lines, :fingerprint, presence: true

  class << self
    def delete_unreferenced(ids)
      return if ids.empty?

      referenced_ids = Notice.where(:backtrace_id.in => ids).distinct(:backtrace_id)
      where(:id.in => ids - referenced_ids).delete_all
    end

    def find_or_build(lines)
      fingerprint = generate_fingerprint(lines)

      backtrace = where(fingerprint: fingerprint).first

      unless backtrace
        backtrace = new(lines: lines)
        backtrace.ensure_fingerprint
      end

      backtrace
    end

    def generate_fingerprint(lines)
      Digest::SHA1.hexdigest(lines.map(&:to_s).join)
    end
  end

  def ensure_fingerprint
    self.fingerprint ||= self.class.generate_fingerprint(lines)
  end
end
