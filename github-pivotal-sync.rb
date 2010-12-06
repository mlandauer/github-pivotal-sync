#!/usr/bin/env ruby

require 'lib/github'
require 'lib/pivotal'
require 'lib/sync'
require 'lib/issue'

require 'open-uri'
require 'rubygems'
require 'json'
require 'yaml'
require 'nokogiri'
require 'rest_client'

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

puts "Retrieving issues..."
sync = Sync.new([Github.new(config["github"]), Pivotal.new(config["pivotal"])])
sync.sync

