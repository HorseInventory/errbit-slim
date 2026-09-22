describe ProblemDestroy do
  let(:problem_destroy) do
    ProblemDestroy.new([problem])
  end

  context "in unit way" do
    let(:problem) { Problem.new }

    describe "#execute" do
      it 'destroy the problem himself' do
        expect(problem).to(receive(:destroy).and_return(true))
        problem_destroy.execute
      end
    end
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
  end
end
