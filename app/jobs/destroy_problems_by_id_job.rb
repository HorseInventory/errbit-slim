class DestroyProblemsByIdJob < ActiveJob::Base
  queue_as :default

  def perform(problem_ids)
    problems = Problem.where(:id.in => problem_ids)
    ::ProblemDestroy.new(problems).execute
  end
end
