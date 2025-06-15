require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'validations' do
    it 'requires a name' do
      user = User.new(name: '', email: 'test@example.com', password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:name]).to include("can't be blank")
    end

    it 'requires unique name' do
      User.create!(name: 'test_user', email: 'test1@example.com', password: 'password123')
      user = User.new(name: 'test_user', email: 'test2@example.com', password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:name]).to include("has already been taken")
    end

    it 'requires valid email' do
      user = User.new(name: 'test_user', email: 'invalid_email', password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("is invalid")
    end

    it 'requires unique email' do
      User.create!(name: 'test_user1', email: 'test@example.com', password: 'password123')
      user = User.new(name: 'test_user2', email: 'test@example.com', password: 'password123')
      expect(user).not_to be_valid
      expect(user.errors[:email]).to include("has already been taken")
    end
  end

  describe 'API token generation' do
    it 'generates an API token on creation' do
      user = User.create!(name: 'test_user', email: 'test@example.com', password: 'password123')
      expect(user.api_token).to be_present
      expect(user.api_token.length).to eq(32)
    end

    it 'generates a unique API token' do
      user1 = User.create!(name: 'test_user1', email: 'test1@example.com', password: 'password123')
      user2 = User.create!(name: 'test_user2', email: 'test2@example.com', password: 'password123')
      expect(user1.api_token).not_to eq(user2.api_token)
    end

    it 'generates token digest on save' do
      user = User.create!(name: 'test_user', email: 'test@example.com', password: 'password123')
      expect(user.token_digest).to be_present
    end
  end

  describe '.find_by_token' do
    let(:user) { User.create!(name: 'test_user', email: 'test@example.com', password: 'password123') }

    it 'finds user by valid token' do
      found_user = User.find_by_token(user.api_token)
      expect(found_user).to eq(user)
    end

    it 'returns nil for invalid token' do
      found_user = User.find_by_token('invalid_token')
      expect(found_user).to be_nil
    end

    it 'returns nil for blank token' do
      found_user = User.find_by_token('')
      expect(found_user).to be_nil
    end

    it 'returns nil for inactive user' do
      user.update!(active: false)
      found_user = User.find_by_token(user.api_token)
      expect(found_user).to be_nil
    end
  end

  describe 'associations' do
    it 'has many request logs' do
      user = User.create!(name: 'test_user', email: 'test@example.com', password: 'password123')
      expect(user).to respond_to(:request_logs)
    end

    it 'destroys associated request logs when user is destroyed' do
      user = User.create!(name: 'test_user', email: 'test@example.com', password: 'password123')
      user.request_logs.create!(
        http_method: 'GET',
        path: '/api/tags',
        ollama_model: 'llama2',
        server_used: 'high_performance',
        response_status: 200,
        response_time_ms: 150.5
      )
      
      expect { user.destroy! }.to change { RequestLog.count }.by(-1)
    end
  end

  describe 'scopes' do
    let!(:active_user) { User.create!(name: 'active_user', email: 'active@example.com', password: 'password123', active: true) }
    let!(:inactive_user) { User.create!(name: 'inactive_user', email: 'inactive@example.com', password: 'password123', active: false) }

    describe '.active' do
      it 'returns only active users' do
        expect(User.active).to include(active_user)
        expect(User.active).not_to include(inactive_user)
      end
    end
  end

  describe 'default values' do
    it 'sets active to true by default' do
      user = User.create!(name: 'test_user', email: 'test@example.com', password: 'password123')
      expect(user.active).to be true
    end
  end
end
