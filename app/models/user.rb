class User
  PER_PAGE = 30
  include Mongoid::Document
  include Mongoid::Timestamps

  devise(*Errbit::Config.devise_modules)

  field :email
  field :name
  field :admin, type: Boolean, default: false
  field :per_page, type: Integer, default: PER_PAGE
  field :time_zone, default: "UTC"

  ## Devise field
  ### Database Authenticatable
  field :encrypted_password, type: String

  ### Recoverable
  field :reset_password_token, type: String
  field :reset_password_sent_at, type: Time

  ### Rememberable
  field :remember_created_at, type: Time

  ### Trackable
  field :sign_in_count,      type: Integer
  field :current_sign_in_at, type: Time
  field :last_sign_in_at,    type: Time
  field :current_sign_in_ip, type: String
  field :last_sign_in_ip,    type: String

  ### Token_authenticatable
  field :authentication_token, type: String

  index authentication_token: 1

  before_save :ensure_authentication_token

  validates :name, presence: true

  if Errbit::Config.user_has_username
    field :username
    validates :username, presence: true
  end

  def per_page
    super || PER_PAGE
  end

  def ensure_authentication_token
    if authentication_token.blank?
      self.authentication_token = generate_authentication_token
    end
  end

  def self.token_authentication_key
    :auth_token
  end

  def reset_password(new_password, new_password_confirmation)
    self.password = new_password
    self.password_confirmation = new_password_confirmation

    self.class.validators_on(:password).map { |v| v.validate_each(self, :password, password) }
    return false if errors.any?

    save(validate: false)
  end

private

  def generate_authentication_token
    loop do
      token = Devise.friendly_token
      break token unless User.where(authentication_token: token).first
    end
  end
end
