describe 'Notice retention' do
  let(:problem) { Fabricate(:problem) }
  let(:backtrace) { Fabricate(:backtrace) }

  def add_notices(count)
    Array.new(count) { Fabricate(:notice, problem: problem, backtrace: backtrace) }
  end

  it 'keeps the newest 100 complete occurrences and preserves all older records and counts' do
    notices = Timecop.freeze(Time.zone.now) { add_notices(103) }
    old_ids = notices.first(3).map(&:id)

    problem.compress_notices

    expect(problem.notices_count).to(eq(103))
    expect(problem.notices.uncompressed.count).to(eq(100))
    expect(problem.notices.where(compressed: true).pluck(:id)).to(match_array(old_ids))
    old = notices.first.reload
    expect(old.server_environment).to(eq({}))
    expect(old.request).to(eq({}))
    expect(old.notifier).to(eq({}))
    expect(old.error_class).to(be_nil)
    expect(old.backtrace_id).to(be_nil)
    expect(old.message).to(eq('FooError: Too Much Bar'))
    expect(old.fingerprint).to(be_present)
    expect(notices.last.reload.backtrace).to(eq(backtrace))
  end

  it 'does not update already compressed history and compresses only the next excess occurrence' do
    add_notices(102)
    problem.compress_notices

    commands = record_mongo_commands { problem.compress_notices }
    expect(commands.none? { |command| command.key?('update') || command.key?('delete') }).to(be(true))
    expect(commands.find { |command| command['find'] == 'notices' }['filter']['compressed']).to(be(false))

    next_oldest = problem.notices.uncompressed.ordered.first
    add_notices(1)
    problem.compress_notices

    expect(next_oldest.reload.compressed).to(be(true))
    expect(problem.notices.uncompressed.count).to(eq(100))
    expect(problem.notices_count).to(eq(103))
  end

  it 'removes an unused backtrace without deleting one shared with another Problem' do
    unused = Fabricate(:notice, problem: problem)
    unused_backtrace_id = unused.backtrace_id
    shared = Fabricate(:notice, problem: problem)
    other = Fabricate(:notice, backtrace: shared.backtrace)
    add_notices(100)

    problem.compress_notices

    expect(Backtrace.where(id: unused_backtrace_id)).not_to(exist)
    expect(other.reload.backtrace).to(be_present)
    expect(shared.reload.backtrace_id).to(be_nil)
  end

  it 'keeps only the latest occurrence when resolving and preserves its shared backtrace' do
    notices = add_notices(3)
    other = Fabricate(:notice, backtrace: backtrace)

    problem.resolve!

    expect(problem.reload.notices.pluck(:id)).to(eq([notices.last.id]))
    expect(notices.last.reload.backtrace).to(eq(backtrace))
    expect(other.reload.backtrace).to(eq(backtrace))
  end

  it 'retains the newest 100 full occurrences after merging Problems' do
    add_notices(60)
    other_problem = Fabricate(:problem)
    60.times { Fabricate(:notice, problem: other_problem, backtrace: backtrace) }

    ProblemMerge.new(problem, other_problem).merge

    expect(problem.notices_count).to(eq(120))
    expect(problem.notices.uncompressed.count).to(eq(100))
    expect(Backtrace.where(id: backtrace.id)).to(exist)
  end
end
