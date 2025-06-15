require 'rails_helper'

RSpec.describe HealthController, type: :controller do
  describe 'GET #check' do
    before do
      # Mock the ollama_proxy configuration
      allow(Rails.application.config).to receive(:ollama_proxy).and_return({
        servers: {
          high_performance: {
            host: 'localhost',
            port: 11435,
            enabled: true,
            priority: 1,
            max_memory_gb: nil
          },
          legacy: {
            host: 'localhost',
            port: 11436,
            enabled: true,
            priority: 2,
            max_memory_gb: 8
          }
        },
        external_hosts: {
          openai: {
            host: 'api.openai.com',
            port: 443,
            protocol: 'https',
            enabled: false
          }
        }
      })
    end

    it 'returns health status without authentication' do
      # Mock HTTParty responses for server health checks
      allow(HTTParty).to receive(:get).and_return(
        double(success?: true, code: 200)
      )

      get :check

      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('application/json')
    end

    it 'includes server status information' do
      # Mock HTTParty responses
      allow(HTTParty).to receive(:get).with('http://localhost:11435/', timeout: 5)
                                     .and_return(double(success?: true, code: 200))
      allow(HTTParty).to receive(:get).with('http://localhost:11436/', timeout: 5)
                                     .and_return(double(success?: true, code: 200))

      get :check

      json_response = JSON.parse(response.body)

      expect(json_response).to have_key('status')
      expect(json_response).to have_key('timestamp')
      expect(json_response).to have_key('servers')
      expect(json_response['status']).to eq('ok')
      expect(json_response['servers']).to have_key('high_performance')
      expect(json_response['servers']).to have_key('legacy')
    end

    it 'handles server connection failures gracefully' do
      # Mock HTTParty to raise an exception
      allow(HTTParty).to receive(:get).and_raise(StandardError.new('Connection refused'))

      get :check

      expect(response).to have_http_status(:success)
      json_response = JSON.parse(response.body)
      expect(json_response['status']).to eq('ok')

      # Should still return server info even if checks fail
      expect(json_response).to have_key('servers')
    end

    it 'includes response time information for healthy servers' do
      # Mock successful response with timing
      start_time = Time.current
      allow(Time).to receive(:current).and_return(start_time, start_time + 0.1)
      allow(HTTParty).to receive(:get).and_return(double(success?: true, code: 200))

      get :check

      json_response = JSON.parse(response.body)
      server_status = json_response['servers']['high_performance']

      expect(server_status).to have_key('response_time_ms')
      expect(server_status).to have_key('status')
      expect(server_status['status']).to eq('healthy')
    end

    it 'marks servers as unhealthy when they return error codes' do
      # Mock failed response
      allow(HTTParty).to receive(:get).and_return(double(success?: false, code: 500))

      get :check

      json_response = JSON.parse(response.body)
      server_status = json_response['servers']['high_performance']

      expect(server_status['status']).to eq('unhealthy')
    end

    it 'includes server configuration information' do
      allow(HTTParty).to receive(:get).and_return(double(success?: true, code: 200))

      get :check

      json_response = JSON.parse(response.body)
      hp_server = json_response['servers']['high_performance']
      legacy_server = json_response['servers']['legacy']

      expect(hp_server).to have_key('priority')
      expect(hp_server).to have_key('max_memory_gb')
      expect(legacy_server['priority']).to eq(2)
      expect(legacy_server['max_memory_gb']).to eq(8)
    end
  end
end
