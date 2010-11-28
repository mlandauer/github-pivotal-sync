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
  
  # Returns number of new issue
  def new_issue(title)
    result = YAML.load(RestClient.post("https://github.com/api/v2/yaml/issues/open/#{@repository}", :login => @username,
      :token => @api_token, :title => title))
    result["issue"]["number"]
  end
  
  # issues/edit/:user/:repo/:number
  def edit_issue(id, title)
    RestClient.post("https://github.com/api/v2/yaml/issues/edit/#{@repository}/#{id}", :login => @username,
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
  
  def edit_issue(id, title)
    RestClient.put("https://www.pivotaltracker.com/services/v3/projects/#{@project_id}/stories/#{id}", {:story => {:name => title}},
      "X-TrackerToken" => @token)
  end
end

# Given an array of values return the first found value that appears multiple times
# If no duplicates are found return nil
def first_duplicate(a)
  a.uniq.each do |i|
    return i if a.select {|j| i == j}.count > 1
  end
  nil
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

puts "Checking for duplicate titles..."
# First check that there are no tickets with duplicate titles
duplicate_title = first_duplicate(github_issues.map{|i| i.title})
if duplicate_title
  puts "Warning: There are multiple GitHub issues with the same title: #{duplicate_title}. Please merge them manually into one and rerun the sync."
  exit
end 
duplicate_title = first_duplicate(pivotal_issues.map{|i| i.title})
if duplicate_title
  puts "Warning: There are multiple Pivotal Tracker stories with the same title: #{duplicate_title}. Please merge them manually into one and rerun the sync."
  exit
end 

synched = []

if File.exist?("issue-sync-store.yaml")
  puts "Reading sync store..."
  store = File.open("issue-sync-store.yaml") do |f|
    YAML.load(f.read)
  end
  # For each issue in the store see if any of them have changed title
  store.each do |store_issue|
    github_issue = github_issues.find {|i| i.github_id == store_issue.github_id}
    pivotal_issue = pivotal_issues.find {|i| i.pivotal_id == store_issue.pivotal_id}
    if github_issue.nil? || pivotal_issue.nil?
      # The issue has been deleted. Keep the issue in the sync store to ensure that it doesn't get recreated
      synched << store_issue
    else
      github_changed = (store_issue.title != github_issue.title)
      pivotal_changed = (store_issue.title != pivotal_issue.title)
      if github_changed && pivotal_changed
        puts "Warning: The issue with the title '#{store_issue.title} was changed to '#{github_issue.title}' on GitHub and '#{pivotal_issue}' on Pivotal Tracker. As both of them were changed we can't sync the changes"
        synched << store_issue
      elsif github_changed
        puts "On pivotal need to change issue #{store_issue.pivotal_id} from '#{store_issue.title}' to '#{github_issue.title}'"
        p.edit_issue(store_issue.pivotal_id, github_issue.title)
        synched << Issue.new(github_issue.title, store_issue.github_id, store_issue.pivotal_id)
      elsif pivotal_changed
        puts "On github need to change issue #{store_issue.github_id} from '#{store_issue.title}' to '#{pivotal_issue.title}'"
        g.edit_issue(store_issue.github_id, pivotal_issue.title)
        synched << Issue.new(pivotal_issue.title, store_issue.github_id, store_issue.pivotal_id)
      else
        synched << store_issue
      end
    end
    github_issues.delete_if {|i| i.github_id == store_issue.github_id}
    pivotal_issues.delete_if {|i| i.pivotal_id == store_issue.pivotal_id}
  end
end

# Any issues we see from here on we don't know anything about. i.e. we haven't seen them before and we haven't stored their
# id's in the sync store

matching_titles = github_issues.map{|i| i.title} & pivotal_issues.map{|i| i.title}

# We assume tickets with matching titles have been synced. So, we remove them from our list to process
matching_titles.each do |t|
  synched << Issue.new(t, github_issues.find{|i| i.title == t}.github_id, pivotal_issues.find{|i| i.title == t}.pivotal_id)
  github_issues.delete_if {|i| i.title == t}
  pivotal_issues.delete_if {|i| i.title == t}
end

# Now, remaining tickets in the github list need to be added to pivotal and vice versa
puts "Adding new stories to Pivotal Tracker..." unless github_issues.empty?
github_issues.each do |i|
  pivotal_id = p.new_issue(i.title)
  synched << Issue.new(i.title, i.github_id, pivotal_id)
end

puts "Adding new issues to GitHub..." unless pivotal_issues.empty?
pivotal_issues.each do |i|
  github_id = g.new_issue(i.title)
  synched << Issue.new(i.title, github_id, i.pivotal_id)
end

# Write out the issue sync store
puts "Writing issue sync store..."
File.open("issue-sync-store.yaml", "w") do |f|
  f.write(YAML.dump(synched))
end
