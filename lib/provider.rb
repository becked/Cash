require 'open_uri.rb'

class Provider

  attr_reader :entries
  
  ################
  # Initialization
  def initialize
    @entries = nil
    @remote  = nil
    @name    = "provider"
    @url     = "#{PROVIDER_CONFIG["prot"]}://#{PROVIDER_CONFIG["host"]}#{PROVIDER_CONFIG["path"]}"
    @authentication = PROVIDER_CONFIG["auth"]
  end
  def get_connection
    DaemonKit.logger.info "Connecting #{@name}"
    @remote ||= open("#{PROVIDER_CONFIG["prot"]}://#{PROVIDER_CONFIG["host"]}#{PROVIDER_CONFIG["path"]}",
                :http_basic_authentication => @authentication,
                :read_timeout => 1600)
  end
  def run
    get_connection
    to_cache
  end


  ################
  # Caching
  def generate_base_key(entry)
    "provider:#{entry.first.to_s.downcase}"
  end

  def generate_relation_entry_key(entry)
    Digest::SHA1.hexdigest(entry.to_s)
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each { |entry| cache_entry(entry) }
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
  end

  def cache_relation(base_key, relation, entry)
    begin
      key = "#{base_key}:#{relation}"

      # CactusAppointments are sets of hashes
      if entry.is_a? Array
        entry.each do |e|
          sub_key = "#{key}:#{generate_relation_entry_key(e)}"
          sub_result = $redis.multi do
            $redis.mapped_hmset(sub_key, e)
            $redis.expire(sub_key, OPTIONS[:ttl])
          end
          $redis.sadd(key, sub_key) if sub_result.all? { |e| e.to_s =~ /^(1|OK)$/ }
        end
        return key unless $redis.smembers(key).empty?

      # Provider is a hash
      else
        result = $redis.multi do
          $redis.mapped_hmset(key, entry)
          $redis.expire(key, OPTIONS[:ttl])
        end
        return key if result.all? { |e| e.to_s =~ /^(1|OK)$/ }
      end
      return false

    rescue => e
      DaemonKit.logger.error "mapped_hmset: #{e.inspect} => (#{key} , #{entry.inspect})"
    end
  end



  def cache_entry(entry)
    base_key = generate_base_key(entry)
    %w(cactus_appointments provider).each do |relation|
      if entry.last.has_key?(relation)
        if sub_key = cache_relation(base_key, relation, entry.last[relation])
          $redis.sadd(base_key, sub_key)
        end

        # Reverse index on last_name and lifenumber
        if "provider" == relation
          $redis.sadd("last_name:#{entry.last["provider"]["lastname"].downcase}", base_key) unless entry.last["provider"]["lastname"].blank?
          $redis.sadd("lifenumber:#{entry.last["provider"]["lifenumber"].downcase}", base_key) unless entry.last["provider"]["lifenumber"].blank?
        end
      end
    end
    # Reverse index on provider_k
    $redis.sadd("provider_k:#{entry.last["provider"]["provider_k"].downcase}", base_key)
  end

  # Maintenance
  # TODO this
  def vacuum
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
  end
end
