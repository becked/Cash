class LdapDirectory

  ATTRIBUTES = [:last_name, :lifenumber, :login_id, :mail]
  CONVERSIONS = {
    :employeeid           => :lifenumber,
    :employeenumber       => :lifenumber,
    :givenname            => :first_name,
    :mailalternateaddress => :aliases,
    :mailalias            => :aliases,
    :o                    => :department,
    :proxyaddresses       => :aliases,
    :samaccountname       => :login_id,
    :sn                   => :last_name,
    :uid                  => :login_id,
    :useraccountcontrol   => :status,
    :mailuserstatus       => :status,
    :memberof             => :groups,
    :lastlogontimestamp   => :last_login,
    :accountexpires       => :account_expires,
    :info                 => :sponsor
  }

  ################
  # Initialization
  def initialize
    @name = self.name
    @config = LDAP_CONFIG.send(@name)
    @ldap = get_connection
    @entries = nil
  end
  def get_connection
    @config.servers.sort_by {rand}.each do |server|
      return Net::LDAP.new(
        :host       => server,
        :base       => @config.base,
        :port       => @config.port,
        :encryption => @config.encryption,
        :auth => {
          :method   => :simple,
          :username => @config.username,
          :password => @config.password })
    end
  end

  def run
    to_cache
    vacuum
  end

  ################
  # Caching
  def generate_key(entry)
    if entry.has_key? :login_id
      "#{@name}:#{entry[:login_id]}".downcase
    else
      "#{@name}:#{entry[:mail]}".downcase
    end
  end

  def to_cache
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= self.to_h
    DaemonKit.logger.info "Adding #{@name}"
    @entries.each { |entry| cache_entry(entry) }
    DaemonKit.logger.info "Finished: #{@entries.length} #{@name}"
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

  ################
  # Search
  def filter
    Net::LDAP::Filter.construct @config.user_filter
  end
  def to_h
    @result = @ldap.search(:filter => filter, :attributes => @config.attributes) do |entry|
      yield(translate(entry.to_h)) if block_given?
    end
    @result.map { |e| translate(e.to_h) }
  end
  def translate(entry)
    entry[:directory] = @name
    entry = entry.keys.select do |key|
      CONVERSIONS.include? key
    end.inject({}) { |hash,key| hash[CONVERSIONS[key]] = entry[key]; hash }.merge(entry)
    if @config.has_key? :lifenumber_attribute
      entry[:lifenumber] = entry[@config.lifenumber_attribute]
    end
    if entry.has_key?(:last_login)
      begin
        entry[:last_login] = ad_to_time(entry[:last_login])
      rescue => e
        DaemonKit.logger.error "last_login: #{e.inspect} => (#{entry.inspect})"
      end
    end
    if entry.has_key?(:account_expires)
      begin
        entry[:account_expires] = ad_to_time(entry[:account_expires])
      rescue => e
        DaemonKit.logger.error "account_expires: #{e.inspect} => (#{entry.inspect})"
      end
    end
    if entry.has_key?(:groups)
      begin
        parsed = Yajl::Parser.parse(entry[:groups])
      rescue
        parsed = Array(entry[:groups])
      end
      groups = parsed.map { |e| e.match(/^cn=([^,]+),/i)[1] rescue nil }.delete_if { |e| e.blank? } rescue []
      entry[:groups] = Yajl::Encoder.encode(groups)
    end

    entry
  end

  ################
  # Meta
  def method_missing(method, *args, &block)
    @ldap.send(method, *args, &block)
  end

  def name
    self.class.to_s.sub(/Directory$/, "").downcase
  end

  def ad_to_time(time)
    time = time.first if time.class == Array
    time = time.to_s
    return "" if (time.to_i == 0) || (time.to_i >= 9223371252000000000)

    case time
    when /^\d*$/
      Time.at((time.to_i - 116_444_736_000_000_000) / 10_000_000)
    when /^\d{14}\.0Z$/
      begin
        Time.parse time
      rescue
        ''
      end
    else
      ''
    end
  end

  ################
  # Maintenance
  def vacuum
    DaemonKit.logger.info "Loading #{@name}"
    @entries ||= self.to_h
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
