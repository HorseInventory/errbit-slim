describe ProblemAggregationSorter do
  let(:app) { Fabricate(:app) }

  def page(sort, order = 'asc', number = 1, per_page = 30)
    described_class.call(criteria: app.problems.unresolved, sort: sort, order: order, page: number, per_page: per_page)
  end

  it 'loads row statistics and the shared App with a fixed number of queries for every sort' do
    5.times do |i|
      problem = Fabricate(:problem, app: app, message: "Problem #{i}")
      Fabricate(:notice, problem: problem)
    end

    ['message', 'environment', 'created_at', 'count', 'last_notice_at'].each do |sort|
      commands = record_mongo_commands do
        page(sort).each do |problem|
          expect(problem.app.name).to(eq(app.name))
          expect(problem.notices_count).to(eq(1))
          expect(problem.first_notice_at).to(eq(problem.last_notice_at))
        end
      end

      expect(commands.count { |command| command['find'] == 'apps' }).to(eq(1))
      expect(commands.count { |command| command['find'] == 'problems' }).to(eq(1))
      expect(commands.count { |command| command['aggregate'] == 'problems' }).to(eq(1))
      expect(commands.none? { |command| command['find'] == 'notices' || command['aggregate'] == 'notices' }).to(be(true))
    end
  end

  it 'sorts messages in both directions and paginates with the correct total' do
    problems = ['Alpha', 'Bravo', 'Charlie'].map { |message| Fabricate(:problem, app: app, message: message) }
    Fabricate(:problem, app: app, message: 'Hidden', resolved: true)

    expect(page('message').map(&:id)).to(eq(problems.map(&:id)))
    expect(page('message', 'desc').map(&:id)).to(eq(problems.reverse.map(&:id)))
    second = page('message', 'asc', 2, 2)
    expect(second.map(&:id)).to(eq([problems.last.id]))
    expect(second.total_count).to(eq(3))
    expect(page('message', 'asc', 3, 2)).to(be_empty)
  end

  it 'handles an empty result and Problems with no occurrences' do
    expect(page('count')).to(be_empty)
    problem = Fabricate(:problem, app: app)

    ['message', 'count', 'last_notice_at'].each do |sort|
      result = page(sort)
      expect(result.map(&:id)).to(eq([problem.id]))
      expect(result.first.notices_count).to(eq(0))
      expect(result.first.first_notice_at).to(be_nil)
      expect(result.first.last_notice_at).to(be_nil)
    end
  end
end
