#!/usr/bin/env ruby

require 'open-uri'
require 'rubygems'
require 'json'
require 'yaml'

# First, demonstrate that we can grab all the open issues from GitHub

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

github_username = config["github"]["username"]
github_api_token = config["github"]["api_token"]
github_repository = config["github"]["repository"]

github = open("https://github.com/api/v2/json/issues/list/#{github_repository}/open",
  :http_basic_authentication=>["#{github_username}/token", github_api_token]) do |f|
  JSON.parse(f.read)
end

github["issues"].each do |issue|
  number = issue["number"]
  title = issue["title"]
  puts "id: #{number}, title: #{title}"
end