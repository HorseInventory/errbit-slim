describe ProblemMerge do
  let(:problem) { Fabricate(:problem_with_notices).reload }
  let(:problem_1) { Fabricate(:problem_with_notices).reload }

  describe "#merge" do
    let!(:problem_merge) do
      ProblemMerge.new(problem, problem_1)
    end

    it 'deletes the child problem' do
      expect do
        problem_merge.merge
      end.to change(Problem, :count).by(-1)

      expect(Problem.where(id: problem_1.id)).to be_empty
    end

    it 'moves all notices into the merged problem' do
      notice_ids = Notice.where(:problem_id.in => [problem.id, problem_1.id]).pluck(:id)

      problem_merge.merge

      expect(Notice.where(problem_id: problem.id).pluck(:id)).to contain_exactly(*notice_ids)
    end
  end
end
