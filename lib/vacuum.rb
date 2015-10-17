class Vacuum
  PREFIXES = [:last_name, :lifenumber, :login_id, :mail, :msmcid, :mssmid, :mssm_imail, :hosp_ad, :hosp_novell]

  class << self
    def run
      DaemonKit.logger.info "Vacuuming all"
      PREFIXES.each do |prefix|
        $redis.keys("#{prefix}:*").each do |key|
          clean(key)
        end
      end
      DaemonKit.logger.info "Vacuuming done"
    end

    def clean(key)
      smembers = $redis.smembers(key)
      smembers.each do |member|
        if $redis.exists(member)

          # FIXME Doesn't work on sinaicentral
          next unless $redis.type(member) == "hash"
          # FIXME Doesn't work on mail
          next if key.split(":").first == "mail"

          entry = $redis.hgetall(member)
          entry_first = entry[key.split(":").first]
          key_last = key.split(":").last
          if entry_first and key_last
            if entry[key.split(":").first].downcase != key.split(":").last.downcase
              $redis.srem(key, member)
              DaemonKit.logger.info "Deleting member #{key} => #{member}"
            end
          end
        else
          $redis.srem(key, member)
          DaemonKit.logger.info "Deleting member #{key} => #{member}"
        end
      end
      if $redis.scard(key) == 0
        DaemonKit.logger.info "Deleting key #{key}"
        $redis.del(key)
      end
    end
  end
end
