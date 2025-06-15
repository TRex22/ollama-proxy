class HealthController < ApplicationController
  skip_before_action :authenticate_user!

  def check
    render json: {
      status: 'ok',
      timestamp: Time.current.iso8601,
      servers: server_health_status,
      external_hosts: external_hosts_status
    }
  end

  private

  def server_health_status
    config = Rails.application.config.ollama_proxy[:servers] || {}
    
    config.map do |server_name, server_config|
      next unless server_config[:enabled]
      
      [server_name, check_server_health(server_config)]
    end.compact.to_h
  end

  def external_hosts_status
    config = Rails.application.config.ollama_proxy[:external_hosts] || {}
    
    config.map do |host_name, host_config|
      next unless host_config[:enabled]
      
      [host_name, check_external_host_health(host_config)]
    end.compact.to_h
  end

  def check_server_health(server_config)
    start_time = Time.current
    
    begin
      response = HTTParty.get(
        "http://#{server_config[:host]}:#{server_config[:port]}/",
        timeout: 5
      )
      
      response_time = ((Time.current - start_time) * 1000).round(2)

      {
        status: response.success? ? 'healthy' : 'unhealthy',
        response_time_ms: response_time,
        priority: server_config[:priority],
        max_memory_gb: server_config[:max_memory_gb]
      }
    rescue => e
      {
        status: 'unhealthy',
        error: e.message,
        priority: server_config[:priority],
        max_memory_gb: server_config[:max_memory_gb]
      }
    end
  end

  def check_external_host_health(host_config)
    start_time = Time.current
    protocol = host_config[:protocol] || 'https'
    
    begin
      response = HTTParty.get(
        "#{protocol}://#{host_config[:host]}:#{host_config[:port]}/",
        timeout: 5
      )
      
      response_time = ((Time.current - start_time) * 1000).round(2)

      {
        status: response.code < 500 ? 'healthy' : 'unhealthy',
        response_time_ms: response_time,
        protocol: protocol
      }
    rescue => e
      {
        status: 'unhealthy',
        error: e.message,
        protocol: protocol
      }
    end
  end
end