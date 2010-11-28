#!/usr/bin/env ruby

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


class Repo
  attr_accessor :issues_to_be_synched

  def mark_as_synched(id)
    @issues_to_be_synched.delete_if {|i| i.repo_id == id}
  end

  def find_issue_to_be_synched(id)
    @issues_to_be_synched.find {|i| i.repo_id == id}
  end
end

class Github < Repo
  attr_reader :open_issues

  def initialize(config)
    @username = config["username"]
    @api_token = config["api_token"]
    @repository = config["repository"]

    github = open("https://github.com/api/v2/json/issues/list/#{@repository}/open",
      :http_basic_authentication=>["#{@username}/token", @api_token]) do |f|
      JSON.parse(f.read)
    end

    @open_issues = github["issues"].map do |issue|
      Issue.new(issue["title"], issue["number"])
    end
    @issues_to_be_synched = @open_issues
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
  
  def system_name
    "GitHub"
  end
  
  def issues_name
    "GitHub issues"
  end
  
  def tag
    :github
  end
end

class Pivotal < Repo
  attr_reader :open_issues, :issues_to_be_synched
  
  def initialize(config)
    @username = config["username"]
    @password = config["password"]
    @project = config["project"]
    
    @token = Nokogiri::XML(open("https://www.pivotaltracker.com/services/v3/tokens/active",
      :http_basic_authentication => [@username, @password])).at('guid').inner_text
    @project_id = api_v3("projects").search('project').find {|p| p.at('name').inner_text == @project}.at('id').inner_text
    @open_issues = api_v3("projects/#{@project_id}/stories").search('story').map do |s|
      Issue.new(s.at('name').inner_text, s.at('id').inner_text)
    end
    @issues_to_be_synched = @open_issues
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
  
  def system_name
    "Pivotal Tracker"
  end
  
  def issues_name
    "Pivotal Tracker Stories"
  end
  
  def tag
    :pivotal
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

# Returns an array of all the duplicate values in an array
# e.g. [1, 2, 3, 1, 4, 5, 6, 3, 7] => [1, 3]
def all_duplicates(a)
  a.uniq.select{|v| a.select{|b| b == v}.count > 1}
end

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

puts "Retrieving issues..."
g = Github.new(config["github"])
p = Pivotal.new(config["pivotal"])
s = [g, p]

puts "Checking for duplicate titles..."
s.each do |r|
  duplicate_title = first_duplicate(r.open_issues.map{|i| i.title})
  if duplicate_title
    puts "Warning: There are multiple #{r.issues_name} with the same title: #{duplicate_title}. Please merge them manually into one and rerun the sync."
    exit
  end 
end

synched = []

if File.exist?("issue-sync-store.yaml")
  puts "Reading sync store..."
  store = File.open("issue-sync-store.yaml") do |f|
    YAML.load(f.read)
  end
  # For each issue in the store see if any of them have changed title
  store.each do |store_issue|
    issues = s.map {|t| t.find_issue_to_be_synched(store_issue.ids[t.tag])}
    
    # If some of the issues couldn't be found - i.e. have been deleted in the meantime
    if issues.compact != issues
      # The issue has been deleted. Keep the issue in the sync store to ensure that it doesn't get recreated
      synched << store_issue
    else
      issues_changed = issues.map{|i| store_issue.title != i.title}

      if issues_changed.select{|b| b}.count > 1
        puts "Warning: The issue with the title '#{store_issue.title}' was changed in more than one place to different values:"
        s.each do |t|
          issue = t.find_issue_to_be_synched(store_issue.ids[t.tag])
          puts "  On #{t.system_name} it was changed to '#{issue.title}'" if issue.title != store_issue.title
        end
        puts "  That means that unfortunately we can't sync the changes automatically"
        synched << store_issue
      elsif issues_changed.select{|b| b}.count == 1
        s.each do |t|
          issue = t.find_issue_to_be_synched(store_issue.ids[t.tag])
          if issue.title != store_issue.title
            # Update the title on the other systems
            (s - [t]).each do |repo|
              puts "On #{repo.system_name} changing issue #{store_issue.ids[repo.tag]} from '#{store_issue.title}' to '#{issue.title}'"
              repo.edit_issue(store_issue.ids[repo.tag], issue.title)
              synched << SynchedIssue.new(issue.title, store_issue.ids)
            end
          end
        end
      else
        synched << store_issue
      end
    end
    s.each do |t|
      t.mark_as_synched(store_issue.ids[t.tag])
    end
  end
end

# Any issues we see from here on we don't know anything about. i.e. we haven't seen them before and we haven't stored their
# id's in the sync store

all_titles = s.map do |t|
  t.issues_to_be_synched.map{|i| i.title}
end.flatten

# We can do this because we can be sure that there is only one of a particular title in one repo because we checked for that earlier
matching_titles = all_duplicates(all_titles)

# We assume tickets with matching titles have been synced. So, we remove them from our list to process
matching_titles.each do |t|
  ids = {}

  s.each do |repo|
    matching_issue = repo.issues_to_be_synched.find{|i| i.title == t}
    if matching_issue
      ids[repo.tag] = matching_issue.repo_id
      repo.mark_as_synched(matching_issue.repo_id)
    end
  end

  synched << SynchedIssue.new(t, ids)
end

# Now, remaining tickets in the github list need to be added to pivotal and vice versa
s.each do |repo|
  puts "Synching new issues added on #{repo.system_name}..." unless repo.issues_to_be_synched.empty?
  repo.issues_to_be_synched.each do |i|
    ids = {}
    s.map do |t|
      ids[t.tag] = (t == repo ? i.repo_id : t.new_issue(i.title))
    end
    synched << SynchedIssue.new(i.title, ids)
  end
end

# Write out the issue sync store
puts "Writing issue sync store..."
File.open("issue-sync-store.yaml", "w") do |f|
  f.write(YAML.dump(synched))
end
