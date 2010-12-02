class Repo
  attr_accessor :issues_to_be_synched

  def mark_as_synched(id)
    @issues_to_be_synched.delete_if {|i| i.repo_id == id}
  end

  def find_issue_to_be_synched(id)
    @issues_to_be_synched.find {|i| i.repo_id == id}
  end
end
