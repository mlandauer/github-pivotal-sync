require 'lib/repo'

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
