class ProblemAggregationSorter
  NOTICE_SORTS = {
    'count'          => 'notice_statistics.notices_count',
    'last_notice_at' => 'notice_statistics.last_notice_at',
  }.freeze

  class << self
    def call(criteria:, sort:, order:, page:, per_page:)
      new(criteria, sort, order, page, per_page).call
    end
  end

  def initialize(criteria, sort, order, page, per_page)
    @criteria = criteria
    @sort = sort
    @direction = order == 'asc' ? 1 : -1
    @page = [page.to_i, 1].max
    @per_page = per_page
  end

  def call
    result = Problem.collection.aggregate([
      { '$match' => @criteria.selector },
      { '$facet' => { 'meta' => [{ '$count' => 'total' }], 'data' => page_pipeline } },
    ]).first

    rows = result.fetch('data')
    total = result.fetch('meta').sum { |row| row.fetch('total') }
    problems = Problem.where(:id.in => rows.map { |row| row.fetch('_id') }).includes(:app).index_by(&:id)
    decorated = rows.map do |row|
      ProblemDecorator.new(
        problems.fetch(row.fetch('_id')),
        context: { notice_statistics: row.fetch('notice_statistics') },
      )
    end

    Kaminari.paginate_array(decorated, total_count: total).page(@page).per(@per_page)
  end

private

  def page_pipeline
    pagination = [
      { '$sort' => { NOTICE_SORTS.fetch(@sort, @sort) => @direction, '_id' => 1 } },
      { '$skip' => (@page - 1) * @per_page },
      { '$limit' => @per_page },
    ]
    stages = if NOTICE_SORTS.key?(@sort)
      notice_statistics + pagination
    else
      pagination + notice_statistics
    end
    stages + [{ '$project' => { '_id' => 1, 'notice_statistics' => 1 } }]
  end

  def notice_statistics
    [
      {
        '$lookup' => {
          'from'     => Notice.collection.name,
          'let'      => { 'problem_id' => '$_id' },
          'pipeline' => [
            { '$match' => { '$expr' => { '$eq' => ['$problem_id', '$$problem_id'] } } },
            { '$group' => Notice::STATISTICS_GROUP },
          ],
          'as'       => 'notice_statistics',
        },
      },
      {
        '$addFields' => {
          'notice_statistics' => {
            '$ifNull' => [{ '$arrayElemAt' => ['$notice_statistics', 0] }, Notice::EMPTY_STATISTICS],
          },
        },
      },
    ]
  end
end
