require 'open_uri.rb'

class Sinaicentral

  attr_reader :entries
  
  SYSTEM_NAMES = %w(msmcid mssmid mssm_imail hosp_ad hosp_novell)

  ################
  # Initialization
  def initialize
    @entries = nil
    @remote  = nil
    @name    = "sinaicentral"
    @url     = "#{SC_CONFIG["prot"]}://#{SC_CONFIG["host"]}#{SC_CONFIG["path"]}"
    @authentication = SC_CONFIG["auth"]
  end
  def get_connection
    @remote ||= open("#{SC_CONFIG["prot"]}://#{SC_CONFIG["host"]}#{SC_CONFIG["path"]}",
                :http_basic_authentication => @authentication,
                :read_timeout => 2500)
  end
  def run
    get_connection
    to_cache
  end


  ################
  # Caching
  def generate_base_key(entry)
    "sinaicentral:#{entry.first}"
  end

  def generate_relation_entry_key(entry)
    Digest::SHA1.hexdigest(entry.to_s)
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each do |entry|
      attempts = 0
      begin
        cache_entry(format_entry(entry))
      rescue
        attempts += 1
        DaemonKit.logger.info "Retrying: #{attempts}"
        retry unless attempts > 10
      end
    end
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
  end

  def format_entry(entry)
    entry.last["employee"]["lifenumber"] = entry.last["employee"]["lifenumber"].ceil.to_s rescue ""
    if entry.last["employee"]["lifenumber"].nil? or entry.last["employee"]["lifenumber"].empty?
    	entry.last["employee"]["lifenumber"] = entry.last["employee"]["security_id"].downcase rescue ""
    end
    return entry
  end

  def cache_relation(base_key, relation, entry)
    begin
      key = "#{base_key}:#{relation}"

      # TODO Managers should be sets of the managers' base_keys
      # Appointments and system_ids are sets of hashes
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

      # Employee is a hash
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
    %w(appointments employee managers system_ids linked_account).each do |relation|
      if entry.last.has_key?(relation)
        if sub_key = cache_relation(base_key, relation, entry.last[relation])
          $redis.sadd(base_key, sub_key)
        end

        # Reverse index on last_name, lifenumber, and login_id
        if "employee" == relation
          $redis.sadd("last_name:#{entry.last["employee"]["last_name"].downcase}", base_key) unless entry.last["employee"]["last_name"].blank?
          $redis.sadd("lifenumber:#{entry.last["employee"]["lifenumber"]}", base_key)        unless entry.last["employee"]["lifenumber"].blank?
        end

        if "appointments" == relation
          entry.last["appointments"].each do |appointment|
            begin
              if appointment["department_code"] and appointment["department_code"].any?
                $redis.sadd("department_code:#{appointment["department_code"].downcase}", base_key)
              end
            rescue => e
              puts appointment.inspect
              puts e.inspect
              puts
              next
            end
          end
        end

        if "system_ids" == relation
          entry.last["system_ids"].each do |system_id|
            if SYSTEM_NAMES.include?(system_id["system_name"].downcase) and system_id["system_id"].any?
              # TODO: Verify that the indexed account has a life number that matches back first
              #       (to avoid the dandre01 issue).
              $redis.sadd("login_id:#{system_id["system_id"].downcase}", base_key)
            end
          end
        end
      end
    end
    # Reverse index on sc_userid
    $redis.sadd("sc_userid:#{entry.last["employee"]["sc_userid"]}", base_key)
  end

  # Maintenance
  # TODO this
  def vacuum
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
  end
end
