require 'rails_helper'

RSpec.describe ProxyController, type: :controller do
  let(:user) { User.create!(name: 'test_user', email: 'test@example.com', password: 'password123') }

  before do
    request.headers['Authorization'] = "Bearer #{user.api_token}"
    
    # Mock the ollama_proxy configuration
    allow(Rails.application.config).to receive(:ollama_proxy).and_return({
      servers: {
        high_performance: {
          host: 'localhost',
          port: 11435,
          name: 'high_performance',
          enabled: true,
          priority: 1,
          max_memory_gb: nil
        },
        legacy: {
          host: 'localhost',
          port: 11436,
          name: 'legacy',
          enabled: true,
          priority: 2,
          max_memory_gb: 8
        }
      },
      model_config: {
        explicit_assignments: {
          'gpt-4' => 'openai'
        },
        memory_overrides: {
          'custom-model' => 10.0
        },
        memory_patterns: [
          { pattern: '.*-7b.*', memory_gb: 4.5 },
          { pattern: '.*-70b.*', memory_gb: 40.0 }
        ],
        default_memory_gb: 4.5,
        cache_model_info: false
      },
      request_timeout: 300,
      model_info_timeout: 10,
      server_busy_threshold_ms: 1000
    })
  end

  describe 'POST #forward' do
    context 'with authentication' do
      it 'forwards requests to backend server' do
        # Mock successful HTTParty response
        mock_response = double(
          code: 200,
          body: '{"models": []}',
          headers: { 'content-type' => 'application/json' },
          success?: true
        )
        
        allow(HTTParty).to receive(:get).and_return(mock_response)
        allow(HTTParty).to receive(:post).and_return(mock_response)
        
        post :forward, params: { path: 'api/generate' }
        
        expect(response).to have_http_status(:success)
      end

      it 'logs the request' do
        mock_response = double(
          code: 200,
          body: '{}',
          headers: { 'content-type' => 'application/json' },
          success?: true
        )
        
        allow(HTTParty).to receive(:get).and_return(mock_response)
        allow(HTTParty).to receive(:post).and_return(mock_response)
        
        expect {
          post :forward, params: { path: 'api/generate' }
        }.to change { RequestLog.count }.by(1)
      end

      it 'handles server errors gracefully' do
        allow(HTTParty).to receive(:get).and_raise(StandardError.new('Connection failed'))
        
        post :forward, params: { path: 'api/generate' }
        
        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Internal server error')
      end
    end

    context 'without authentication' do
      before do
        request.headers['Authorization'] = nil
      end

      it 'returns unauthorized status' do
        post :forward, params: { path: 'api/generate' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'model name extraction' do
    it 'extracts model from generate request body' do
      allow(request).to receive(:path).and_return('/api/generate')
      allow(request).to receive(:raw_post).and_return('{"model": "llama2", "prompt": "test"}')
      
      model_name = controller.send(:extract_model_name)
      expect(model_name).to eq('llama2')
    end

    it 'extracts model from chat request body' do
      allow(request).to receive(:path).and_return('/api/chat')
      allow(request).to receive(:raw_post).and_return('{"model": "mistral:7b", "messages": []}')
      
      model_name = controller.send(:extract_model_name)
      expect(model_name).to eq('mistral:7b')
    end

    it 'handles invalid JSON gracefully' do
      allow(request).to receive(:path).and_return('/api/generate')
      allow(request).to receive(:raw_post).and_return('invalid json')
      
      model_name = controller.send(:extract_model_name)
      expect(model_name).to be_nil
    end

    it 'returns nil for paths without model info' do
      allow(request).to receive(:path).and_return('/api/tags')
      
      model_name = controller.send(:extract_model_name)
      expect(model_name).to be_nil
    end
  end

  describe 'memory requirements calculation' do
    it 'uses memory overrides when available' do
      memory = controller.send(:get_model_memory_requirements, 'custom-model')
      expect(memory).to eq(10.0)
    end

    it 'uses pattern matching for unknown models' do
      memory = controller.send(:get_model_memory_requirements, 'llama2-7b-chat')
      expect(memory).to eq(4.5)
    end

    it 'uses default memory for unmatched models' do
      memory = controller.send(:get_model_memory_requirements, 'unknown-model')
      expect(memory).to eq(4.5)
    end

    it 'returns default for nil model name' do
      memory = controller.send(:get_model_memory_requirements, nil)
      expect(memory).to eq(4.5)
    end
  end

  describe 'server selection' do
    before do
      # Mock server availability checks
      allow(controller).to receive(:server_available?).and_return(true)
      allow(controller).to receive(:get_model_memory_requirements).and_return(4.5)
    end

    it 'selects high performance server by default' do
      server = controller.send(:select_server, 'llama2')
      expect(server[:name]).to eq('high_performance')
    end

    it 'respects memory constraints' do
      # Mock a large model that exceeds legacy server capacity
      allow(controller).to receive(:get_model_memory_requirements).and_return(15.0)
      
      server = controller.send(:select_server, 'large-model-70b')
      expect(server[:name]).to eq('high_performance')
    end

    it 'falls back to legacy server when high performance is unavailable' do
      allow(controller).to receive(:server_available?).with(
        hash_including(name: 'high_performance')
      ).and_return(false)
      allow(controller).to receive(:server_available?).with(
        hash_including(name: 'legacy')
      ).and_return(true)
      
      server = controller.send(:select_server, 'llama2')
      expect(server[:name]).to eq('legacy')
    end
  end

  describe 'URL building' do
    it 'constructs proper URLs for servers' do
      server_config = { host: 'localhost', port: 11435, protocol: 'http' }
      allow(request).to receive(:path).and_return('/api/generate')
      allow(request).to receive(:query_string).and_return('')
      
      url = controller.send(:build_request_url, server_config)
      expect(url).to eq('http://localhost:11435/api/generate')
    end

    it 'includes query parameters' do
      server_config = { host: 'localhost', port: 11435 }
      allow(request).to receive(:path).and_return('/api/tags')
      allow(request).to receive(:query_string).and_return('format=json')
      
      url = controller.send(:build_request_url, server_config)
      expect(url).to eq('http://localhost:11435/api/tags?format=json')
    end

    it 'defaults to http protocol' do
      server_config = { host: 'localhost', port: 11435 }
      allow(request).to receive(:path).and_return('/api/tags')
      allow(request).to receive(:query_string).and_return('')
      
      url = controller.send(:build_request_url, server_config)
      expect(url).to start_with('http://')
    end
  end
end