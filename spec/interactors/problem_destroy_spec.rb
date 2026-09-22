describe ProblemDestroy do
  let(:problem_destroy) do
    ProblemDestroy.new(Problem.where(id: problem.id))
  end

  context "in integration way" do
    let!(:problem) { Fabricate(:problem) }
    let!(:notice_1_1) { Fabricate(:notice, problem: problem) }
    let!(:notice_1_2) { Fabricate(:notice, problem: problem) }

    it 'should all destroy' do
      problem_destroy.execute
      expect(Problem.where(_id: problem.id).entries).to(be_empty)
      expect(Notice.where(_id: notice_1_1.id).entries).to(be_empty)
      expect(Notice.where(_id: notice_1_2.id).entries).to(be_empty)
    end

    it 'deletes occurrences in bulk and only removes their unused backtraces' do
      shared = notice_1_1.backtrace
      other_notice = Fabricate(:notice, backtrace: shared)
      unrelated_backtrace = Fabricate(:backtrace)
      unused_id = notice_1_2.backtrace_id

      commands = record_mongo_commands { problem_destroy.execute }

      expect(Notice.where(id: other_notice.id)).to(exist)
      expect(Backtrace.where(id: shared.id)).to(exist)
      expect(Backtrace.where(id: unrelated_backtrace.id)).to(exist)
      expect(Backtrace.where(id: unused_id)).not_to(exist)
      notice_deletes = commands.select { |command| command['delete'] == 'notices' }
      expect(notice_deletes.size).to(eq(1))
      expect(notice_deletes.first['deletes'].first['limit']).to(eq(0))
      expect(commands.none? { |command| command['find'] == 'notices' }).to(be(true))
    end

    it 'uses the same bulk occurrence cleanup when destroying an app' do
      backtrace_ids = [notice_1_1.backtrace_id, notice_1_2.backtrace_id]
      problem.app.destroy

      expect(Problem.where(id: problem.id)).not_to(exist)
      expect(Notice.where(problem_id: problem.id)).not_to(exist)
      expect(Backtrace.where(:id.in => backtrace_ids)).not_to(exist)
    end

    it 'does not delete a Problem added to the scope after deletion begins' do
      app = problem.app
      arriving_notice = nil
      allow(NoticeDestroy).to(receive(:new).and_wrap_original do |constructor, notices|
        arriving_notice = Fabricate(:notice, problem: Fabricate(:problem, app: app))
        constructor.call(notices)
      end)

      ProblemDestroy.new(app.problems).execute

      expect(Notice.where(id: arriving_notice.id)).to(exist)
      expect(Problem.where(id: arriving_notice.problem_id)).to(exist)
      expect(Problem.where(id: problem.id)).not_to(exist)
    end
  end
end
