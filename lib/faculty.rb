require 'open_uri.rb'

class Faculty

  attr_reader :entries
  
  ################
  # Initialization
  def initialize
    @entries = nil
    @remote  = nil
    @name    = "faculty"
    @url     = "#{FACULTY_CONFIG["prot"]}://#{FACULTY_CONFIG["host"]}#{FACULTY_CONFIG["path"]}"
    @authentication = FACULTY_CONFIG["auth"]
  end
  def get_connection
    DaemonKit.logger.info "Connecting #{@name}"
    @remote ||= open("#{FACULTY_CONFIG["prot"]}://#{FACULTY_CONFIG["host"]}#{FACULTY_CONFIG["path"]}",
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
    "faculty:#{entry.first.to_i.to_s}"
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

# >> faculty.first.last["person"]
# => {"fid"=>15508.0, "degree"=>"M.D.", "last"=>"Smego", "facstatus"=>"I", "first"=>"Douglas R.", "lifenum"=>"1956245"}
# >> faculty.first.last["ap_appointments"]
# => [{"executive_faculty_approved"=>"2006-09-28T00:00:00Z", "fid"=>15508.0, "terminated_date"=>"2008-02-29T00:00:00Z", "title"=>"INSTRUCTOR", "division"=>nil, "term_start"=>"2006-07-01T00:00:00Z", "dept"=>"CARDIOTHORACIC SURGERY", "term_end"=>"2007-06-30T00:00:00Z"}]

  def cache_relation(base_key, relation, entry)
    begin
      key = "#{base_key}:#{relation}"

      # ApAppointments are sets of hashes
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

      # Person is a hash
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
    %w(ap_appointments person).each do |relation|
      if entry.last.has_key?(relation)
        if sub_key = cache_relation(base_key, relation, entry.last[relation])
          $redis.sadd(base_key, sub_key)
        end

        # Reverse index on last_name and lifenumber
        if "person" == relation
          $redis.sadd("last_name:#{entry.last["person"]["last"].downcase}", base_key) unless entry.last["person"]["last"].blank?
          $redis.sadd("lifenumber:#{entry.last["person"]["lifenum"].downcase}", base_key) unless entry.last["person"]["lifenum"].blank?
        end
      end
    end
    # Reverse index on sc_userid
    $redis.sadd("fid:#{entry.last["person"]["fid"]}", base_key)
  end

  # Maintenance
  # TODO this
  def vacuum
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
  end
end
