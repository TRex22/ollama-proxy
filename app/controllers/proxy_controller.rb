class ProxyController < ApplicationController
  def forward
    start_time = Time.current
    model_name = extract_model_name
    server_config = select_server(model_name)

    Rails.logger.info "Routing request to #{server_config[:name]} server for model: #{model_name || 'unknown'}"

    response = forward_request(server_config)
    response_time = ((Time.current - start_time) * 1000).round(2)

    log_request(
      ollama_model: model_name,
      server_used: server_config[:name],
      response_status: response.code,
      response_time_ms: response_time
    )

    render_proxy_response(response)

  rescue => e
    response_time = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.error "Proxy error: #{e.message}"

    log_request(
      ollama_model: model_name,
      server_used: server_config&.dig(:name),
      response_status: 500,
      response_time_ms: response_time,
      error_message: e.message
    )

    render json: { error: 'Internal server error' }, status: 500
  end

  private

  def extract_model_name
    # Try to extract model name from various Ollama API endpoints
    if request.path.include?('/api/generate') || request.path.include?('/api/chat')
      begin
        body = JSON.parse(request.raw_post) if request.raw_post.present?
        return body['model'] if body&.key?('model')
      rescue JSON::ParserError
        # Ignore JSON parse errors
      end
    elsif request.path.match(%r{/api/pull|/api/push|/api/show})
      # Extract from query params or body
      return params[:name] || params[:model]
    end

    nil
  end

  def select_server(model_name)
    config = Rails.application.config.ollama_proxy
    
    # Check for explicit assignments first
    if model_name && config[:model_config][:explicit_assignments]&.key?(model_name)
      server_name = config[:model_config][:explicit_assignments][model_name]
      
      # Check if it's an external host
      if config[:external_hosts]&.key?(server_name.to_sym)
        external_config = config[:external_hosts][server_name.to_sym]
        return external_config.merge(name: server_name) if external_config[:enabled]
      end
      
      # Check if it's a regular server
      if config[:servers]&.key?(server_name.to_sym)
        server_config = config[:servers][server_name.to_sym]
        return server_config if server_config[:enabled]
      end
    end

    # Get model memory requirements
    model_memory_gb = get_model_memory_requirements(model_name)
    
    # Filter servers by memory constraints and availability
    available_servers = config[:servers].select do |name, server_config|
      server_config[:enabled] &&
      (server_config[:max_memory_gb].nil? || model_memory_gb <= server_config[:max_memory_gb]) &&
      server_available?(server_config)
    end

    if available_servers.empty?
      Rails.logger.warn "No available servers for model #{model_name}, falling back to first enabled server"
      fallback_server = config[:servers].find { |name, server| server[:enabled] }
      return fallback_server[1] if fallback_server
      raise "No enabled servers configured"
    end

    # Sort by priority (lower number = higher priority) and select the best one
    selected_server = available_servers.min_by { |name, server_config| server_config[:priority] || 999 }
    
    Rails.logger.info "Selected #{selected_server[0]} server for model #{model_name || 'unknown'}"
    selected_server[1]
  end

  def get_model_memory_requirements(model_name)
    return Rails.application.config.ollama_proxy[:model_config][:default_memory_gb] unless model_name

    config = Rails.application.config.ollama_proxy[:model_config]
    
    # Check memory overrides first
    if config[:memory_overrides]&.key?(model_name)
      return config[:memory_overrides][model_name]
    end

    # Try to get from cached model info or fetch from servers
    memory_gb = fetch_model_memory_from_servers(model_name)
    return memory_gb if memory_gb

    # Use pattern matching as fallback
    if config[:memory_patterns]
      config[:memory_patterns].each do |pattern_config|
        if model_name.match?(Regexp.new(pattern_config[:pattern]))
          return pattern_config[:memory_gb]
        end
      end
    end

    # Final fallback
    config[:default_memory_gb] || 4.5
  end

  def fetch_model_memory_from_servers(model_name)
    config = Rails.application.config.ollama_proxy
    cache_key = "model_memory_#{model_name}"
    
    # Check cache first if enabled
    if config[:model_config][:cache_model_info]
      cached_memory = Rails.cache.read(cache_key)
      return cached_memory if cached_memory
    end

    # Try to fetch from each enabled server
    config[:servers].each do |server_name, server_config|
      next unless server_config[:enabled]
      
      begin
        response = HTTParty.get(
          "http://#{server_config[:host]}:#{server_config[:port]}/api/tags",
          timeout: config[:model_info_timeout] || 10
        )
        
        if response.success?
          models = JSON.parse(response.body)['models'] || []
          model_info = models.find { |m| m['name'] == model_name }
          
          if model_info && model_info['size']
            # Convert bytes to GB
            memory_gb = (model_info['size'].to_f / (1024**3)).round(1)
            
            # Cache the result if caching is enabled
            if config[:model_config][:cache_model_info]
              Rails.cache.write(cache_key, memory_gb, expires_in: config[:model_config][:cache_ttl_seconds] || 3600)
            end
            
            return memory_gb
          end
        end
      rescue => e
        Rails.logger.warn "Failed to fetch model info from #{server_name}: #{e.message}"
      end
    end

    nil
  end

  def server_available?(server_config)
    return false unless server_config[:enabled]
    
    config = Rails.application.config.ollama_proxy
    start_time = Time.current
    
    begin
      response = HTTParty.get(
        "http://#{server_config[:host]}:#{server_config[:port]}/",
        timeout: 2
      )
      
      response_time = Time.current - start_time
      response.success? && response_time < (config[:server_busy_threshold_ms] || 1000) / 1000.0
    rescue
      false
    end
  end

  def forward_request(server_config)
    url = build_request_url(server_config)
    
    options = {
      timeout: Rails.application.config.ollama_proxy[:request_timeout] || 300,
      headers: forward_headers(server_config)
    }

    case request.method.upcase
    when 'GET'
      HTTParty.get(url, options)
    when 'POST'
      HTTParty.post(url, options.merge(body: request.raw_post))
    when 'PUT'
      HTTParty.put(url, options.merge(body: request.raw_post))
    when 'DELETE'
      HTTParty.delete(url, options)
    when 'PATCH'
      HTTParty.patch(url, options.merge(body: request.raw_post))
    else
      HTTParty.send(request.method.downcase, url, options.merge(body: request.raw_post))
    end
  end

  def build_request_url(server_config)
    protocol = server_config[:protocol] || 'http'
    host = server_config[:host]
    port = server_config[:port]
    
    url = "#{protocol}://#{host}:#{port}#{request.path}"
    url += "?#{request.query_string}" if request.query_string.present?
    url
  end

  def forward_headers(server_config)
    # Forward relevant headers, excluding hop-by-hop headers
    headers_to_forward = request.headers.to_h.select do |key, value|
      key.start_with?('HTTP_') &&
      !['HTTP_AUTHORIZATION', 'HTTP_HOST', 'HTTP_VERSION'].include?(key)
    end

    # Convert back to standard header format
    forwarded_headers = headers_to_forward.transform_keys do |key| 
      key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-') 
    end

    # Add API key for external services
    if server_config[:api_key_env]
      api_key = ENV[server_config[:api_key_env]]
      if api_key.present?
        forwarded_headers['Authorization'] = "Bearer #{api_key}"
      else
        Rails.logger.warn "API key environment variable #{server_config[:api_key_env]} not set"
      end
    end

    forwarded_headers
  end

  def render_proxy_response(response)
    # Forward the response status and body
    response_headers = response.headers.to_h.except('transfer-encoding', 'connection')

    response_headers.each do |key, value|
      response.set_header(key, value) unless ['transfer-encoding', 'connection'].include?(key.downcase)
    end

    render body: response.body, status: response.code, content_type: response.headers['content-type']
  end
end