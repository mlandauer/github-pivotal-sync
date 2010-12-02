#!/usr/bin/env ruby

require 'lib/github'
require 'lib/pivotal'

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

class Sync
  attr_reader :s

  def initialize(s)
    @s = s
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

  def sync
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
  end
end

config = open("configuration.yaml") do |f|
  YAML.load(f.read)
end

puts "Retrieving issues..."
sync = Sync.new([Github.new(config["github"]), Pivotal.new(config["pivotal"])])
sync.sync

