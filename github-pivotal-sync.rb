#!/usr/bin/env ruby

require 'lib/github'
require 'lib/pivotal'
require 'lib/sync'

require 'open-uri'
require 'rubygems'
require 'json'
require 'yaml'
require 'nokogiri'
require 'rest_client'

class SynchedIssue
  attr_accessor :title, :ids
  def initialize(title, ids)
    @title, @ids = title, ids
  end
end

class Issue
  attr_accessor :title, :repo_id
  def initialize(title, repo_id)
    @title, @repo_id = title, repo_id
  end
end

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

puts "Retrieving issues..."
sync = Sync.new([Github.new(config["github"]), Pivotal.new(config["pivotal"])])
sync.sync

