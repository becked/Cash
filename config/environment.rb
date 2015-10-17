# Boot up
require File.join(File.dirname(__FILE__), 'boot')
require 'rubygems'
require 'digest'
require 'net/ldap'
require 'open-uri'
gem 'redis', '=2.1.1'
require 'redis'
require 'yajl'
require 'yaml'

DaemonKit::Initializer.run do |config|
  config.daemon_name = "cash"
end

CHIEF_CONFIG = DaemonKit::Config.hash("chief")
REDIS_CONFIG = DaemonKit::Config.hash("redis")
LDAP_CONFIG = DaemonKit::Config.hash("ldap")
ISIS_CONFIG = DaemonKit::Config.hash("isis")
SC_CONFIG = DaemonKit::Config.hash("sinaicentral")
BB_CONFIG = DaemonKit::Config.hash("blackboard")
FACULTY_CONFIG  = DaemonKit::Config.hash("faculty")
PROVIDER_CONFIG  = DaemonKit::Config.hash("provider")

$redis = Redis.new(:host => REDIS_CONFIG["host"], :timout => 12000000)
puts $redis.inspect

DIRECTORIES = [:example]

OPTIONS = {
  :sleep => 300,
  :ttl   => 86400
}

