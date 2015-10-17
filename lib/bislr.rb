require "open_uri.rb"

class Bislr
  ATTRIBUTES = [:last_name]


  ################
  # Initialization
  def initialize
    @entries = nil
    @remote = nil
    @name = "bislr"
    @url     = "https://#{CHIEF_CONFIG["host"]}#{CHIEF_CONFIG["path"]}/bislr_employees.json"
    @authentication = CHIEF_CONFIG["auth"]
  end
  def get_connection
    @remote ||= open(@url,
                :http_basic_authentication => @authentication,
                :read_timeout => 600)
  end
  def run
    get_connection
    to_cache
  end

  ################
  # Caching
  def generate_key(entry)
    "#{@name}:#{entry[:employee_number]}"
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= Yajl::Parser.parse(@remote.read)
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each { |entry| cache_entry(format_entry(entry)) }
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
  end

  def format_entry(entry)
    entry["directory"] = @name
    entry.keys.inject({}) { |h,k| h[k.downcase.to_sym] = entry[k]; h }
  end

  def cache_entry(entry)
    key = generate_key(entry)
    retry_cache = 0
    begin
      retry_cache += 1
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
      retry unless retry_cache == 2
      DaemonKit.logger.error "mapped_hmset: #{e.inspect} => (#{key} , #{entry.inspect})"
    end
  end



end
