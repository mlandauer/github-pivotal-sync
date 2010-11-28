#!/usr/bin/env ruby

require 'open-uri'
require 'rubygems'
require 'json'
require 'yaml'
require 'nokogiri'

# First, demonstrate that we can grab all the open issues from GitHub

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

pivotal_username = config["pivotal"]["username"]
pivotal_password = config["pivotal"]["password"]
pivotal_project = config["pivotal"]["project"]

class Issue
  attr_accessor :title, :ids
  def initialize(title, ids)
    @title, @ids = title, ids
  end
end

class Github
  def initialize(config)
    @username = config["username"]
    @api_token = config["api_token"]
    @repository = config["repository"]
  end
  
  def open_issues
    github = open("https://github.com/api/v2/json/issues/list/#{@repository}/open",
      :http_basic_authentication=>["#{@username}/token", @api_token]) do |f|
      JSON.parse(f.read)
    end

    github["issues"].map do |issue|
      Issue.new(issue["title"], :github => issue["number"])
    end
  end
end

g = Github.new(config["github"])

puts "GitHub issues:"
g.open_issues.each do |i|
  puts "id: #{i.ids[:github]}, title: #{i.title}"
end

# Next, demonstrate that we can grab all the open stories from Pivotal Tracker

x = Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/tokens/active",
  :http_basic_authentication => [pivotal_username, pivotal_password]))
token = x.at('guid').inner_text

x = Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/projects", "X-TrackerToken" => token))
project_id = x.search('project').find {|p| p.at('name').inner_text == pivotal_project}.at('id').inner_text

x = Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/projects/#{project_id}/stories", "X-TrackerToken" => token))

puts "Pivotal Stories:"
x.search('story').each do |s|
  id = s.at('id').inner_text
  name = s.at('name').inner_text
  puts "id: #{id}, title: #{name}"
end
