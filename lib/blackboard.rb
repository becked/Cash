require "open_uri.rb"
require "xmlsimple"

class Blackboard
  ATTRIBUTES = [:last_name, :lifenumber, :login_id]
  CONVERSION = {
    :loginname     => :login_id,
    :lastname      => :last_name,
    :firstname     => :first_name,
    :firstname     => :first_name,
    :lastlogindate => :last_login
  }

  ################
  # Initialization
  def initialize
    @entries = nil
    @remote = nil
    @name = "blackboard"
    @url     = "https://#{BB_CONFIG["host"]}#{BB_CONFIG["path"]}"
    @authentication = BB_CONFIG["auth"]
  end
  def get_connection
    @remote ||= open(@url,
                :http_basic_authentication => @authentication,
                :read_timeout => 600)
  end
  def load_entries
    data = XmlSimple.xml_in(@remote.read)
    @entries = data["PERSON"].map { |e| format_entry(e) }
  end

  def run
    get_connection
    load_entries
    to_cache
    vacuum
  end

  ################
  # Caching
  def generate_key(entry)
    "#{@name}:#{entry[:login_id]}"
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each { |entry| cache_entry(entry) }
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
  end

  def format_entry(entry)
    entry["directory"] = @name
    entry.keys.inject({}) { |h,k| h[CONVERSION[k.downcase.to_sym] || k.downcase.to_sym] = entry[k].first; h }
  end

  def cache_entry(entry)
    return unless entry[:login_id] and entry[:login_id].any?
    key = generate_key(entry)
    begin
      # Save entry with an expiration
      $redis.multi do
        $redis.mapped_hmset(key, entry)
        $redis.expire(key, OPTIONS[:ttl])
      end

      # Add to reverse index for select attributes
      ATTRIBUTES.each do |attribute|
        next if entry[attribute].blank?
        begin
          value = entry[attribute].first.downcase
          $redis.sadd("#{attribute}:#{value}", key)
        rescue => e
          DaemonKit.logger.error "sadd: #{e.inspect} => #{attribute}:#{value} - #{entry.inspect}"
        end
      end
    rescue => e
      DaemonKit.logger.error "mapped_hmset: #{e.inspect} => (#{key} , #{entry.inspect})"
    end
  end

  ################
  # Maintenance
  def vacuum
    DaemonKit.logger.info "Loading #{@name}"
    current_keys = @entries.map { |e| generate_key(e) }
    DaemonKit.logger.info "Vacuuming #{@name}"
    count = 0
    cached_keys.each do |cached_key|
      unless current_keys.include?(cached_key)
        $redis.del(cached_key)
        count += 1
      end
    end
    DaemonKit.logger.info "Vaccumed: #{count} #{@name}"
  end

  def cached_keys
    $redis.keys("#{@name}:*")
  end

  def clean_entry( entry )
    key = generate_key(entry)
    unless $redis.exists( key )
      ATTRIBUTES.each do |attribute|
        next if entry[attribute].blank?
        begin
          value = entry[attribute].first.downcase
          $redis.srem( "#{attribute}:#{value}", key )
          return true
        rescue => e
          DaemonKit.logger.error "srem: #{e.inspect} => #{attribute}:#{value}"
        end
      end
    end
    false
  end

end
