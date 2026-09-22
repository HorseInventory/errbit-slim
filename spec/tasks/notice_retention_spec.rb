require 'rake'

describe 'errbit:prepare_notice_retention' do
  before(:all) do
    load Rails.root.join('lib/tasks/errbit/notice_retention.rake')
    Rake::Task.define_task(:environment)
  end

  it 'marks existing records without deleting occurrences or shared backtraces' do
    old = Fabricate(:notice)
    full = Fabricate(:notice, backtrace: old.backtrace)
    unreferenced = Fabricate(:notice)
    unused_backtrace_id = unreferenced.backtrace_id
    Notice.collection.find('_id' => { '$in' => [old.id, unreferenced.id] }).update_many(
      '$set' => { server_environment: {}, notifier: {}, request: nil },
    )
    Notice.collection.find.update_many('$unset' => { 'compressed' => '' })

    task = Rake::Task['errbit:prepare_notice_retention']
    task.reenable
    task.invoke

    expect(Notice.count).to(eq(3))
    expect(old.reload.compressed).to(be(true))
    expect(old.backtrace_id).to(be_nil)
    expect(full.reload.compressed).to(be(false))
    expect(full.backtrace).to(be_present)
    expect(Backtrace.where(id: unused_backtrace_id)).not_to(exist)
    expect(Notice.collection.indexes.to_a.map { |index| index['key'] }).to(include(
      { 'problem_id' => 1, 'compressed' => 1, 'created_at' => 1, '_id' => 1 },
    ))
  end
end
