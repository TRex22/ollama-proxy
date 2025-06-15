# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Setup Commands
```bash
# Initial setup
bundle install
rails db:create db:migrate

# Development server
rails server

# Production server
RAILS_ENV=production rails server
```

### Testing Commands
```bash
# Run full test suite
rspec

# Run specific test types
rspec spec/controllers/
rspec spec/models/

# Code quality checks
bundle exec rubocop
bundle exec brakeman
```

### User Management
```bash
# Create new user with API token
rails users:create[username]

# List all users
rails users:list

# Show user details
rails users:show[username]

# Deactivate/activate users
rails users:deactivate[username]
rails users:activate[username]

# Regenerate API token
rails users:regenerate_token[username]
```

## Core Architecture

This Rails 8.0.2 API-only application serves as an intelligent proxy server for multiple Ollama instances with sophisticated routing logic.

### Request Flow
1. **Authentication**: Bearer token validation using Devise (ApplicationController)
2. **Intelligent Routing**: Model memory analysis and server selection (ProxyController)
3. **Request Forwarding**: HTTP request proxying with comprehensive logging
4. **Response Handling**: Error handling and performance metrics collection

### Key Components

**ProxyController** - Core routing engine that:
- Analyzes model memory requirements by querying Ollama `/api/tags` endpoints
- Implements priority-based server selection with memory constraints
- Routes specific models to external APIs (OpenAI, Anthropic) via explicit assignments
- Falls back to pattern matching for unknown models
- Handles all HTTP methods (GET, POST, PUT, DELETE, PATCH)

**Configuration System** (`config/ollama_proxy.yml`):
- **servers**: Priority-based server definitions with memory limits
- **external_hosts**: Third-party API integration (OpenAI, Anthropic)
- **model_config**: Explicit assignments, memory overrides, pattern matching
- **logging**: Environment-specific logging configuration

**Authentication**: Devise-based user management with:
- 32-character secure API tokens stored as BCrypt digests
- Constant-time token comparison for security
- User lifecycle management (active/inactive status)

**Request Logging**: Comprehensive logging system capturing:
- HTTP method, path, model used, server routed to
- Response times, status codes, error messages
- User attribution for usage analytics

### Server Selection Algorithm
1. Check explicit model-to-server assignments in config
2. Fetch dynamic model memory requirements from Ollama APIs
3. Filter servers by memory constraints (`max_memory_gb`)
4. Select highest priority available server
5. Fall back to pattern-based memory estimation if API unavailable

### Production Deployment
- Systemd service configuration with security hardening
- Docker support with multi-stage builds
- Structured logging with rotation
- Health monitoring endpoints at `/health`

## Configuration Patterns

**Multi-GPU Setup**: Configure different server priorities and memory limits to route large models to high-performance GPUs and smaller models to legacy hardware.

**External API Integration**: Use `explicit_assignments` in `config/ollama_proxy.yml` to route specific models (e.g., "gpt-4": "openai") to third-party services.

**Memory Pattern Matching**: Define regex patterns in `memory_patterns` to estimate memory requirements for unknown models (e.g., ".*-70b.*": 40.0 GB).

## Testing Strategy

- **Controller specs**: Authentication, routing logic, error handling
- **Model specs**: User management, request logging, token generation
- **Request specs**: End-to-end API functionality
- **Factory Bot**: Test data generation with realistic scenarios
- **HTTParty mocking**: External service integration testing

## Common Development Tasks

When adding new server configurations, update both the `config/ollama_proxy.yml` servers section and ensure corresponding health checks are implemented in HealthController.

When modifying routing logic in ProxyController, update the corresponding RSpec tests in `spec/controllers/proxy_controller_spec.rb` to maintain test coverage of the server selection algorithm.

For external API integrations, add API key environment variables and configure the external_hosts section with proper authentication headers.