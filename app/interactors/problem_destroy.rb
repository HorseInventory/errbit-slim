class ProblemDestroy
  def initialize(problems)
    @problems = problems
  end

  def execute
    problem_ids = @problems.pluck(:id)
    notices = Notice.where(:problem_id.in => problem_ids)
    NoticeDestroy.new(notices).execute
    Problem.where(:id.in => problem_ids).delete_all
  end
end
