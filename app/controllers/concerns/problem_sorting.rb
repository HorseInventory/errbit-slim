module ProblemSorting
  def sort_and_paginate_problems(problems, sort_by, order, page, per_page)
    ProblemAggregationSorter.call(
      criteria: problems,
      sort: sort_by,
      order: order,
      page: page,
      per_page: per_page,
    )
  end
end
