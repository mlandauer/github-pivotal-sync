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

