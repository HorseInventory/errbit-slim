# Sorts + paginates Problems by notice-derived fields (count, last notice time)
# using MongoDB aggregation — no in-memory full-table sort and no extra Problem fields.
class ProblemAggregationSorter
  class << self
    # @param criteria [Mongoid::Criteria] filtered Problem scope (no .page yet)
    # @return Kaminari page of ProblemDecorator with :notices_count / :last_notice_at context
    def call(criteria:, sort:, order:, page:, per_page:)
      page = [page.to_i, 1].max
      per_page = per_page.to_i
      per_page = 25 if per_page <= 0

      dir = order.to_s == "asc" ? 1 : -1
      pipeline = build_pipeline(criteria.selector, sort: sort, order_dir: dir, page: page, per_page: per_page)

      coll = Problem.collection
      result = coll.aggregate(pipeline, allow_disk_use: true).first
      meta = (result && result["meta"]) || []
      data = (result && result["data"]) || []

      total = meta.first ? meta.first["total"].to_i : 0

      decorated = build_decorated_page(data)

      Kaminari.paginate_array(decorated, total_count: total).page(page).per(per_page)
    end

    private

    def build_pipeline(selector, sort:, order_dir:, page:, per_page:)
      skip = (page - 1) * per_page

      [
        { "$match" => selector },
        lookup_notice_stats,
        add_computed_fields,
        sort_stage(sort, order_dir),
        {
          "$facet" => {
            "meta" => [{ "$count" => "total" }],
            "data" => [
              { "$skip" => skip },
              { "$limit" => per_page },
              {
                "$project" => {
                  "_id" => 1,
                  "agg_notices_count" => 1,
                  "agg_last_notice_at" => 1,
                },
              },
            ],
          },
        },
      ]
    end

    def lookup_notice_stats
      {
        "$lookup" => {
          "from" => Notice.collection.name,
          "let" => { "pid" => "$_id" },
          "pipeline" => [
            { "$match" => { "$expr" => { "$eq" => ["$problem_id", "$$pid"] } } },
            {
              "$group" => {
                "_id" => nil,
                "cnt" => { "$sum" => 1 },
                "lastAt" => { "$max" => "$created_at" },
              },
            },
          ],
          "as" => "notice_agg",
        },
      }
    end

    def add_computed_fields
      epoch = Time.zone.at(0)
      {
        "$addFields" => {
          "agg_notices_count" => {
            "$ifNull" => [{ "$arrayElemAt" => ["$notice_agg.cnt", 0] }, 0],
          },
          "agg_last_notice_at" => { "$arrayElemAt" => ["$notice_agg.lastAt", 0] },
          "_sort_last" => {
            "$ifNull" => [{ "$arrayElemAt" => ["$notice_agg.lastAt", 0] }, epoch],
          },
        },
      }
    end

    def sort_stage(sort, order_dir)
      case sort.to_s
      when "count"
        { "$sort" => { "agg_notices_count" => order_dir, "_id" => 1 } }
      when "last_notice_at"
        { "$sort" => { "_sort_last" => order_dir, "_id" => 1 } }
      else
        raise ArgumentError, "Unsupported aggregation sort: #{sort.inspect}"
      end
    end

    def build_decorated_page(rows)
      ids = rows.map { |r| r["_id"] }.compact
      return [] if ids.empty?

      stats_by_id = rows.index_by { |r| r["_id"] }
      problems_by_id = Problem.where(:_id.in => ids).index_by(&:id)

      ids.filter_map do |id|
        problem = problems_by_id[id]
        next unless problem

        row = stats_by_id[id]
        count = row["agg_notices_count"].to_i
        last_at = row["agg_last_notice_at"]
        last_at = last_at.in_time_zone if last_at.respond_to?(:in_time_zone)

        ProblemDecorator.decorate(
          problem,
          context: {
            notices_count: count,
            last_notice_at: last_at,
          },
        )
      end
    end
  end
end
