DaemonKit::Application.running!

def fork_off(&block)
  pid = fork do
    block.call
    exit!
  end
  Process.wait pid
  sleep OPTIONS[:sleep]
end

# Vacuum set keys
if DaemonKit.arguments.options[:vacuum]
  # FIXME - why is this neccessary for cli mode?!
  $redis = Redis.new(:host => REDIS_CONFIG["host"])
  puts $redis.inspect
  Vacuum.run

# Directory mode: grab a single directory once (ugh with the if/else's)
elsif DaemonKit.arguments.options[:directory]
  if DaemonKit.arguments.options[:directory] == :blackboard
    Blackboard.new.run
  elsif DaemonKit.arguments.options[:directory] == :bislr
    Bislr.new.run
  elsif DaemonKit.arguments.options[:directory] == :provider
    Provider.new.run
  elsif DaemonKit.arguments.options[:directory] == :faculty
    Faculty.new.run
  elsif DaemonKit.arguments.options[:directory] == :idx
    Idx.new.run
  elsif DaemonKit.arguments.options[:directory] == :application_certification
    ApplicationCertification.new.run
  elsif DaemonKit.arguments.options[:directory] == :isis
    Isis.new.run
  elsif DaemonKit.arguments.options[:directory] == :mainframe
    Mainframe.new.run
  elsif DaemonKit.arguments.options[:directory] == :new_innovations
    NewInnovations.new.run
  elsif DaemonKit.arguments.options[:directory] == :sinaicentral
    Sinaicentral.new.run
  else
    "#{DaemonKit.arguments.options[:directory].to_s.capitalize}Directory".constantize.new.run
  end

# Normal mode: looping through all our ldap directories
else
  threads = Array.new
  DIRECTORIES.each do |directory|
    threads << Thread.new do
      loop do
        fork_off { "#{directory.to_s.capitalize}Directory".constantize.new.run }
       end
    end
  end
  threads.each { |t| t.join }
end
