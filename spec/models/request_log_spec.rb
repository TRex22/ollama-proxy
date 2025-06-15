require 'rails_helper'

RSpec.describe RequestLog, type: :model do
  let(:user) { User.create!(name: 'test_user', email: 'test@example.com', password: 'password123') }

  describe 'validations' do
    it 'requires a user' do
      log = RequestLog.new(http_method: 'GET', path: '/api/tags')
      expect(log).not_to be_valid
      expect(log.errors[:user]).to include("must exist")
    end

    it 'requires an http_method' do
      log = RequestLog.new(user: user, path: '/api/tags')
      expect(log).not_to be_valid
      expect(log.errors[:http_method]).to include("can't be blank")
    end

    it 'requires a path' do
      log = RequestLog.new(user: user, http_method: 'GET')
      expect(log).not_to be_valid
      expect(log.errors[:path]).to include("can't be blank")
    end

    it 'is valid with required fields' do
      log = RequestLog.new(
        user: user,
        http_method: 'GET',
        path: '/api/tags'
      )
      expect(log).to be_valid
    end
  end

  describe 'associations' do
    it 'belongs to user' do
      log = RequestLog.new
      expect(log).to respond_to(:user)
    end
  end

  describe 'scopes' do
    let!(:recent_log) { RequestLog.create!(user: user, http_method: 'GET', path: '/api/tags', created_at: 1.hour.ago) }
    let!(:old_log) { RequestLog.create!(user: user, http_method: 'POST', path: '/api/generate', created_at: 1.day.ago) }
    let!(:error_log) { RequestLog.create!(user: user, http_method: 'GET', path: '/api/models', response_status: 500) }
    let!(:success_log) { RequestLog.create!(user: user, http_method: 'GET', path: '/api/version', response_status: 200) }

    describe '.recent' do
      it 'orders by created_at desc' do
        logs = RequestLog.recent
        expect(logs.first).to eq(success_log) # most recent
        expect(logs.last).to eq(old_log) # oldest
      end
    end

    describe '.errors' do
      it 'returns logs with error status codes' do
        error_logs = RequestLog.errors
        expect(error_logs).to include(error_log)
        expect(error_logs).not_to include(success_log)
      end

      it 'returns logs with error messages' do
        log_with_error_message = RequestLog.create!(
          user: user,
          http_method: 'GET',
          path: '/api/test',
          response_status: 200,
          error_message: 'Connection timeout'
        )
        
        error_logs = RequestLog.errors
        expect(error_logs).to include(log_with_error_message)
      end
    end

    describe '.for_model' do
      let!(:llama_log) { RequestLog.create!(user: user, http_method: 'POST', path: '/api/generate', ollama_model: 'llama2') }
      let!(:mistral_log) { RequestLog.create!(user: user, http_method: 'POST', path: '/api/generate', ollama_model: 'mistral') }

      it 'returns logs for specific model' do
        llama_logs = RequestLog.for_model('llama2')
        expect(llama_logs).to include(llama_log)
        expect(llama_logs).not_to include(mistral_log)
      end
    end

    describe '.for_server' do
      let!(:hp_log) { RequestLog.create!(user: user, http_method: 'GET', path: '/api/tags', server_used: 'high_performance') }
      let!(:legacy_log) { RequestLog.create!(user: user, http_method: 'GET', path: '/api/tags', server_used: 'legacy') }

      it 'returns logs for specific server' do
        hp_logs = RequestLog.for_server('high_performance')
        expect(hp_logs).to include(hp_log)
        expect(hp_logs).not_to include(legacy_log)
      end
    end
  end

  describe 'attributes' do
    it 'stores request details correctly' do
      log = RequestLog.create!(
        user: user,
        http_method: 'POST',
        path: '/api/generate',
        ollama_model: 'llama2:7b',
        server_used: 'high_performance',
        response_status: 200,
        response_time_ms: 1250.5,
        error_message: nil
      )

      expect(log.http_method).to eq('POST')
      expect(log.path).to eq('/api/generate')
      expect(log.ollama_model).to eq('llama2:7b')
      expect(log.server_used).to eq('high_performance')
      expect(log.response_status).to eq(200)
      expect(log.response_time_ms).to eq(1250.5)
      expect(log.error_message).to be_nil
    end

    it 'handles decimal response times' do
      log = RequestLog.create!(
        user: user,
        http_method: 'GET',
        path: '/api/tags',
        response_time_ms: 123.456
      )

      expect(log.response_time_ms).to eq(123.456)
    end
  end
end
