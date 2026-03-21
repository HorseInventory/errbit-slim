module ProblemSorting
  AGGREGATED_SORTS = %w[last_notice_at count].freeze

  def sort_and_paginate_problems(problems, sort_by, order, page, per_page)
    if AGGREGATED_SORTS.include?(sort_by.to_s)
      ProblemAggregationSorter.call(
        criteria: problems,
        sort: sort_by.to_s,
        order: order.to_s,
        page: page,
        per_page: per_page,
      )
    else
      problems.page(page).per(per_page)
    end
  end
end
