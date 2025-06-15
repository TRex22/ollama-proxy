class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :request_logs, dependent: :destroy
  has_secure_token :api_token, length: 32

  validates :name, presence: true, uniqueness: true
  validates :api_token, presence: true, uniqueness: true

  before_validation :ensure_active_default
  before_save :generate_token_digest

  scope :active, -> { where(active: true) }

  def self.find_by_token(token)
    return nil if token.blank?

    # Find users with token digests and verify with BCrypt
    active.where.not(token_digest: nil).find { |user|
      BCrypt::Password.new(user.token_digest) == token
    }
  end

  private

  def ensure_active_default
    self.active = true if active.nil?
  end

  def generate_token_digest
    self.token_digest = self.class.digest_token(api_token) if api_token_changed?
  end

  def self.digest_token(token)
    BCrypt::Password.create(token).to_s
  end
end
