require 'rails_helper'

# Test controller to verify ApplicationController authentication
class TestController < ApplicationController
  def index
    render json: { message: 'success' }
  end
end

RSpec.describe ApplicationController, type: :controller do
  controller(TestController) do
    def index
      render json: { message: 'success' }
    end
  end

  let(:user) { User.create!(name: 'test_user', email: 'test@example.com', password: 'password123') }

  before do
    routes.draw { get 'index' => 'test#index' }
  end

  describe 'authentication' do
    context 'with valid token' do
      it 'allows access' do
        request.headers['Authorization'] = "Bearer #{user.api_token}"
        get :index

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['message']).to eq('success')
      end

      it 'sets current_user' do
        request.headers['Authorization'] = "Bearer #{user.api_token}"
        get :index

        expect(controller.send(:current_user)).to eq(user)
      end
    end

    context 'with invalid token' do
      it 'returns unauthorized status' do
        request.headers['Authorization'] = "Bearer invalid_token"
        get :index

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns WWW-Authenticate header' do
        request.headers['Authorization'] = "Bearer invalid_token"
        get :index

        expect(response.headers['WWW-Authenticate']).to be_present
      end
    end

    context 'without token' do
      it 'returns unauthorized status' do
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with inactive user' do
      it 'returns unauthorized status' do
        user.update!(active: false)
        request.headers['Authorization'] = "Bearer #{user.api_token}"
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with malformed authorization header' do
      it 'returns unauthorized for missing Bearer prefix' do
        request.headers['Authorization'] = user.api_token
        get :index

        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns unauthorized for empty token' do
        request.headers['Authorization'] = "Bearer "
        get :index

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe '#log_request' do
    before do
      request.headers['Authorization'] = "Bearer #{user.api_token}"
      get :index # This will authenticate the user
      allow(controller).to receive(:request).and_return(
        double(method: 'GET', path: '/api/test')
      )
    end

    it 'creates a request log entry' do
      expect {
        controller.send(:log_request,
          ollama_model: 'llama2',
          server_used: 'high_performance',
          response_status: 200,
          response_time_ms: 150.5
        )
      }.to change { RequestLog.count }.by(1)
    end

    it 'logs request details correctly' do
      controller.send(:log_request,
        ollama_model: 'llama2:7b',
        server_used: 'legacy',
        response_status: 500,
        response_time_ms: 2500.75,
        error_message: 'Connection timeout'
      )

      log = RequestLog.last
      expect(log.user).to eq(user)
      expect(log.http_method).to eq('GET')
      expect(log.path).to eq('/api/test')
      expect(log.ollama_model).to eq('llama2:7b')
      expect(log.server_used).to eq('legacy')
      expect(log.response_status).to eq(500)
      expect(log.response_time_ms).to eq(2500.75)
      expect(log.error_message).to eq('Connection timeout')
    end

    it 'handles logging failures gracefully' do
      # Mock RequestLog.create! to raise an exception
      allow(RequestLog).to receive(:create!).and_raise(StandardError.new('Database error'))

      # Should not raise an exception
      expect {
        controller.send(:log_request, ollama_model: 'test')
      }.not_to raise_error
    end

    it 'logs errors when request logging fails' do
      allow(RequestLog).to receive(:create!).and_raise(StandardError.new('Database error'))

      expect(Rails.logger).to receive(:error).with('Failed to log request: Database error')

      controller.send(:log_request, ollama_model: 'test')
    end
  end
end
