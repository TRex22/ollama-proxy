namespace :users do
  desc "Create a new user with API token"
  task :create, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:create[username]"
      puts "Example: rails users:create[john_doe]"
      exit 1
    end

    # Check if user already exists
    if User.find_by(name: args[:name])
      puts "Error: User '#{args[:name]}' already exists."
      exit 1
    end

    # Create user with a temporary email and password (required by Devise)
    user = User.new(
      name: args[:name],
      email: "#{args[:name]}@ollama-proxy.local",
      password: SecureRandom.hex(16),
      active: true
    )

    if user.save
      puts "✅ User created successfully!"
      puts ""
      puts "Name: #{user.name}"
      puts "API Token: #{user.api_token}"
      puts "Created: #{user.created_at}"
      puts ""
      puts "🔑 Use this token in the Authorization header:"
      puts "Authorization: Bearer #{user.api_token}"
      puts ""
      puts "📋 Example usage:"
      puts "curl -H 'Authorization: Bearer #{user.api_token}' \\"
      puts "     -H 'Content-Type: application/json' \\"
      puts "     -d '{\"model\": \"llama2\", \"prompt\": \"Hello\"}' \\"
      puts "     http://localhost:11434/api/generate"
    else
      puts "❌ Failed to create user:"
      user.errors.full_messages.each { |msg| puts "  - #{msg}" }
      exit 1
    end
  end

  desc "List all users"
  task list: :environment do
    users = User.all.order(:created_at)

    if users.empty?
      puts "No users found. Create one with: rails users:create[username]"
      return
    end

    puts ""
    puts "📋 Ollama Proxy Users"
    puts "=" * 80
    printf "%-20s %-10s %-10s %-32s %s\n", "Name", "Status", "Requests", "Token (preview)", "Created"
    puts "-" * 80

    users.each do |user|
      status = user.active? ? "✅ Active" : "❌ Inactive"
      request_count = user.request_logs.count
      token_preview = "#{user.api_token[0..7]}..."
      created_date = user.created_at.strftime("%Y-%m-%d")

      printf "%-20s %-10s %-10s %-32s %s\n",
             user.name,
             status,
             request_count,
             token_preview,
             created_date
    end

    puts ""
    puts "Total users: #{users.count} (#{users.where(active: true).count} active)"
  end

  desc "Show detailed user information"
  task :show, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:show[username]"
      exit 1
    end

    user = User.find_by(name: args[:name])
    if user.nil?
      puts "❌ User '#{args[:name]}' not found."
      puts ""
      puts "Available users:"
      User.pluck(:name).each { |name| puts "  - #{name}" }
      exit 1
    end

    puts ""
    puts "👤 User Details: #{user.name}"
    puts "=" * 50
    puts "ID: #{user.id}"
    puts "Name: #{user.name}"
    puts "Email: #{user.email}"
    puts "Status: #{user.active? ? '✅ Active' : '❌ Inactive'}"
    puts "API Token: #{user.api_token}"
    puts "Created: #{user.created_at}"
    puts "Updated: #{user.updated_at}"
    puts ""

    # Recent activity
    recent_logs = user.request_logs.recent.limit(10)
    puts "📊 Recent Activity (last 10 requests):"
    puts "-" * 50

    if recent_logs.empty?
      puts "No requests logged yet."
    else
      recent_logs.each do |log|
        status_icon = log.response_status.to_s.start_with?("2") ? "✅" : "❌"
        puts "#{status_icon} #{log.http_method} #{log.path} → #{log.server_used} (#{log.response_status}) #{log.created_at.strftime('%m/%d %H:%M')}"
      end
    end

    puts ""
    puts "📈 Statistics:"
    puts "Total requests: #{user.request_logs.count}"
    puts "Error requests: #{user.request_logs.errors.count}"
    puts "Average response time: #{user.request_logs.average(:response_time_ms)&.round(2) || 'N/A'}ms"
  end

  desc "Activate a user"
  task :activate, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:activate[username]"
      exit 1
    end

    user = User.find_by(name: args[:name])
    if user.nil?
      puts "❌ User '#{args[:name]}' not found."
      exit 1
    end

    if user.active?
      puts "ℹ️  User '#{user.name}' is already active."
    else
      user.update!(active: true)
      puts "✅ User '#{user.name}' has been activated."
    end
  end

  desc "Deactivate a user"
  task :deactivate, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:deactivate[username]"
      exit 1
    end

    user = User.find_by(name: args[:name])
    if user.nil?
      puts "❌ User '#{args[:name]}' not found."
      exit 1
    end

    if !user.active?
      puts "ℹ️  User '#{user.name}' is already inactive."
    else
      user.update!(active: false)
      puts "❌ User '#{user.name}' has been deactivated."
      puts "🔒 All API requests with their token will now be rejected."
    end
  end

  desc "Regenerate API token for a user"
  task :regenerate_token, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:regenerate_token[username]"
      exit 1
    end

    user = User.find_by(name: args[:name])
    if user.nil?
      puts "❌ User '#{args[:name]}' not found."
      exit 1
    end

    old_token = user.api_token[0..7]
    user.regenerate_api_token
    user.save!

    puts "🔄 API token regenerated for user '#{user.name}'"
    puts ""
    puts "Old token: #{old_token}... (now invalid)"
    puts "New token: #{user.api_token}"
    puts ""
    puts "⚠️  Update any applications using the old token!"
  end

  desc "Delete a user (with confirmation)"
  task :delete, [ :name ] => :environment do |t, args|
    if args[:name].blank?
      puts "Usage: rails users:delete[username]"
      exit 1
    end

    user = User.find_by(name: args[:name])
    if user.nil?
      puts "❌ User '#{args[:name]}' not found."
      exit 1
    end

    puts "⚠️  You are about to DELETE user '#{user.name}'"
    puts "This will also delete #{user.request_logs.count} request logs."
    puts ""
    print "Type 'DELETE' to confirm: "

    confirmation = STDIN.gets.chomp
    unless confirmation == "DELETE"
      puts "❌ Deletion cancelled."
      exit 0
    end

    user.destroy!
    puts "🗑️  User '#{args[:name]}' and all associated data have been deleted."
  end

  desc "Clean up old request logs"
  task :cleanup_logs, [ :days ] => :environment do |t, args|
    days = (args[:days] || 30).to_i
    cutoff_date = days.days.ago

    old_logs = RequestLog.where("created_at < ?", cutoff_date)
    count = old_logs.count

    if count == 0
      puts "No logs older than #{days} days found."
      return
    end

    puts "Found #{count} request logs older than #{days} days (before #{cutoff_date.strftime('%Y-%m-%d')})"
    print "Delete them? (y/N): "

    confirmation = STDIN.gets.chomp.downcase
    if confirmation == "y" || confirmation == "yes"
      old_logs.delete_all
      puts "✅ Deleted #{count} old request logs."
    else
      puts "❌ Cleanup cancelled."
    end
  end
end
