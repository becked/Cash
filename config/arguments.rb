# Argument handling for your daemon is configured here.
#
# You have access to two variables when this file is
# parsed. The first is +opts+, which is the object yielded from
# +OptionParser.new+, the second is +@options+ which is a standard
# Ruby hash that is later accessible through
# DaemonKit.arguments.options and can be used in your daemon process.

# Here is an example:
# opts.on('-f', '--foo FOO', 'Set foo') do |foo|
#  @options[:foo] = foo
# end

opts.on("-z", "Vacuum set keys") do |directory|
  @options[:vacuum] = true
end

opts.on("-t", "Do a single run against Trustee") do |directory|
  @options[:directory] = :trustee
end

opts.on("-b", "Do a single run against Blackboard") do |directory|
  @options[:directory] = :blackboard
end

opts.on("-i", "Do a single run against Isis") do |directory|
  @options[:directory] = :isis
end

opts.on("-a", "Do a single run against Bislr") do |directory|
  @options[:directory] = :bislr
end

opts.on("-f", "Do a single run against Faculty") do |directory|
  @options[:directory] = :faculty
end

opts.on("-o", "Do a single run against Provider") do |directory|
  @options[:directory] = :provider
end

opts.on("-r", "Do a single run against Mainframe") do |directory|
  @options[:directory] = :mainframe
end

opts.on("-d", "Do a single run against IDX") do |directory|
  @options[:directory] = :idx
end

opts.on("-p", "Do a single run against Application Certification") do |directory|
  @options[:directory] = :application_certification
end

opts.on("-n", "Do a single run against New Innovations") do |directory|
  @options[:directory] = :new_innovations
end

opts.on("-s", "Do a single run against Sinaicentral") do |directory|
  @options[:directory] = :sinaicentral
end

opts.on("-y", "Do a single run against Example AD Directory") do |directory|
  @options[:directory] = :example
end

opts.on_tail("-h", "--help") do |help|
  puts opts
end
