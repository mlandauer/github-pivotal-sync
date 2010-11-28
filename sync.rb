#!/usr/bin/env ruby

require 'open-uri'
require 'rubygems'
require 'json'
require 'yaml'
require 'nokogiri'
require 'rest_client'

class Issue
  attr_accessor :title, :github_id, :pivotal_id
  def initialize(title, github_id, pivotal_id)
    @title, @github_id, @pivotal_id = title, github_id, pivotal_id
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
      Issue.new(issue["title"], issue["number"], nil)
    end
  end
  
  def new_issue(title)
    RestClient.post("https://github.com/api/v2/yaml/issues/open/#{@repository}", :login => @username,
      :token => @api_token, :title => title) 
  end
end

class Pivotal
  def initialize(config)
    @username = config["username"]
    @password = config["password"]
    @project = config["project"]
    
    @token = Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/tokens/active",
      :http_basic_authentication => [@username, @password])).at('guid').inner_text
    @project_id = api_v3("projects").search('project').find {|p| p.at('name').inner_text == @project}.at('id').inner_text
  end
  
  def open_issues
    api_v3("projects/#{@project_id}/stories").search('story').map do |s|
      Issue.new(s.at('name').inner_text, nil, s.at('id').inner_text)
    end
  end
  
  def api_v3(call)
    Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/#{call}", "X-TrackerToken" => @token))
  end
  
  # Returns id of new issue
  def new_issue(title)
    x = Nokogiri::XML(RestClient.post("https://www.pivotaltracker.com/services/v3/projects/#{@project_id}/stories",
      "<story><name>#{title}</name></story>",
      "X-TrackerToken" => @token, "Content-type" => "application/xml"))
    x.at('id').inner_text
  end
end

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

g = Github.new(config["github"])
p = Pivotal.new(config["pivotal"])

puts "Getting GitHub issues..."
github_issues = g.open_issues
puts "Getting Pivotal Tracker stories..."
pivotal_issues = p.open_issues

# First we proceed as if there has been no previous sync. So, then we have no record of which id's on Github correspond to which id's
# on Pivotal

matching_titles = github_issues.map{|i| i.title} & pivotal_issues.map{|i| i.title}

# We assume tickets with matching titles have been synced. So, we remove them from our list to process
matching_titles.each do |t|
  github_issues.delete_if {|i| i.title == t}
  pivotal_issues.delete_if {|i| i.title == t}
end

# Now, remaining tickets in the github list need to be added to pivotal and vice versa
puts "Adding new stories to Pivotal Tracker..." unless github_issues.empty?
github_issues.each do |i|
  p.new_issue(i.title)
end

puts "Adding new issues to GitHub..." unless pivotal_issues.empty?
pivotal_issues.each do |i|
  g.new_issue(i.title)
end
