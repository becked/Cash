class Net::LDAP::Entry
  def to_h
    @myhash.inject({}) do |h,(k,v)|
      h[k] = (v.length > 1 ? Yajl::Encoder.encode(v.sort) : v.first)
      h
    end
  end
end

class Array
  alias :blank? :empty?
end

class Hash
  alias :blank? :empty?
end

class NilClass
  alias :blank? :nil?
end

class String
  alias :blank? :empty?
  def constantize
    Object.const_get(self)
  end
end

require 'vacuum.rb'
require 'isis.rb'
require 'blackboard.rb'
require 'idx.rb'
require 'application_certification.rb'
require 'mainframe.rb'
require 'new_innovations.rb'
require 'sinaicentral.rb'
require 'bislr.rb'
require 'faculty.rb'
require 'provider.rb'
require 'ldap_directory.rb'

class ExampleDirectory  < LdapDirectory; end

class TrusteeDirectory < LdapDirectory
  def translate(entry)
    if entry[:givenname].blank? and entry[:cn] and entry[:sn] and entry[:cn] != entry[:sn]
      entry[:givenname] = entry[:cn].sub(/#{entry[:sn]}$/, "").strip
    end
    super
  end
end
