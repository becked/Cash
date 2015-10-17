require "open_uri.rb"
require "xmlsimple"

class Isis
  ATTRIBUTES = [:last_name, :lifenumber, :login_id]
  CONVERSION = {
    :mssm_id   => :login_id,
    :lastname  => :last_name,
    :firstname => :first_name
  }

  ################
  # Initialization
  def initialize
    @entries = nil
    @remote = nil
    @name = "isis"
    @url = "https://#{ISIS_CONFIG["host"]}#{ISIS_CONFIG["path"]}"
    @authentication = ISIS_CONFIG["auth"]
  end
  def get_connection
    @remote ||= open(@url,
                :http_basic_authentication => @authentication,
                :read_timeout => 600)
  end
  def run
    get_connection
    to_cache
    # TODO
    # vacuum (copy ldap_directory.rb)
  end

  ################
  # Caching
  def generate_key(entry)
    "#{@name}:#{entry[:isis_id]}-#{entry[:lifenumber]}"
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    data = XmlSimple.xml_in(@remote.read)
    @entries = data["student"]
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each { |entry| cache_entry(format_entry(entry)) }
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
  end

  def format_entry(entry)
    entry["directory"] = @name
    entry.keys.inject({}) { |h,k| h[CONVERSION[k.downcase.to_sym] || k.downcase.to_sym] = entry[k].first; h }
  end

  def cache_entry(entry)
    return unless entry[:login_id] and entry[:login_id].any?
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
