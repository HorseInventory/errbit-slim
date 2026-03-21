describe Problem, type: 'model' do
  # validation on environment removed; environment is computed from latest notice

  describe "Fabrication" do
    context "Fabricate(:problem_with_notices)" do
      it 'should have 3 notices' do
        expect do
          Fabricate(:problem_with_notices)
        end.to(change(Notice, :count).by(3))
      end
    end
  end

  context '#last_notice_at' do
    it "returns the created_at timestamp of the latest notice" do
      problem = Fabricate(:problem)
      expect(problem).to_not(be_nil)

      notice1 = Fabricate(:notice, problem: problem)
      expect(problem.last_notice_at).to(eq(notice1.reload.created_at))

      notice2 = Fabricate(:notice, problem: problem)
      expect(problem.last_notice_at).to(eq(notice2.reload.created_at))
    end
  end

  context '#first_notice_at' do
    it "returns the created_at timestamp of the first notice" do
      problem = Fabricate(:problem)
      expect(problem).to_not(be_nil)

      notice1 = Fabricate(:notice, problem: problem)
      expect(problem.first_notice_at.to_i).to(be_within(1).of(notice1.created_at.to_i))

      Fabricate(:notice, problem: problem)
      expect(problem.first_notice_at.to_i).to(be_within(1).of(notice1.created_at.to_i))
    end
  end

  context 'being created' do
    context 'when the app has err notifications set to false' do
      it 'should not send an email notification' do
        app = Fabricate(:app, notify_on_errs: false)
        expect(Mailer).to_not(receive(:err_notification))
        Fabricate(:problem, app: app)
      end
    end
  end

  context "#resolved?" do
    it "should start out as unresolved" do
      problem = Problem.new
      expect(problem).to_not(be_resolved)
      expect(problem).to(be_unresolved)
    end

    it "should be able to be resolved" do
      problem = Fabricate(:problem)
      expect(problem).to_not(be_resolved)
      problem.resolve!
      expect(problem.reload).to(be_resolved)
    end
  end

  context "resolve!" do
    it "marks the problem as resolved" do
      problem = Fabricate(:problem)
      expect(problem).to_not(be_resolved)
      problem.resolve!
      expect(problem).to(be_resolved)
    end

    it "should record the time when it was resolved" do
      problem = Fabricate(:problem)
      expected_resolved_at = Time.zone.now
      Timecop.freeze(expected_resolved_at) do
        problem.resolve!
      end
      expect(problem.resolved_at.to_s).to(eq(expected_resolved_at.to_s))
    end

    it "should throw an err if it's not successful" do
      problem = Fabricate(:problem)
      expect(problem).to_not(be_resolved)
      allow(problem).to(receive(:valid?).and_return(false))
      ## update_attributes not test #valid? but #errors.any?
      # https://github.com/mongoid/mongoid/blob/master/lib/mongoid/persistence.rb#L137
      er = ActiveModel::Errors.new(problem)
      er.add(:resolved, :blank)
      allow(problem).to(receive(:errors).and_return(er))
      expect(problem).to_not(be_valid)
      expect do
        problem.resolve!
      end.to(raise_error(Mongoid::Errors::Validations))
    end
  end

  context "Scopes" do
    context "ProblemAggregationSorter" do
      it "sorts by last_notice_at desc via aggregation (newest notice first)" do
        app = Fabricate(:app)
        problem1 = Fabricate(:problem, app: app)
        problem2 = Fabricate(:problem, app: app)
        problem3 = Fabricate(:problem, app: app)

        Timecop.freeze(3.days.ago) { Fabricate(:notice, problem: problem1) }
        Timecop.freeze(1.day.ago) { Fabricate(:notice, problem: problem2) }
        Timecop.freeze(2.days.ago) { Fabricate(:notice, problem: problem3) }

        criteria = Problem.for_apps(App.where(id: app.id))
        page = ProblemAggregationSorter.call(
          criteria: criteria,
          sort: "last_notice_at",
          order: "desc",
          page: 1,
          per_page: 10,
        )

        expect(page.map { |d| d.object.id }).to(eq([problem2.id, problem3.id, problem1.id]))
      end

      it "sorts by notices count desc via aggregation" do
        app = Fabricate(:app)
        low = Fabricate(:problem, app: app)
        high = Fabricate(:problem, app: app)
        mid = Fabricate(:problem, app: app)

        2.times { Fabricate(:notice, problem: low) }
        5.times { Fabricate(:notice, problem: high) }
        3.times { Fabricate(:notice, problem: mid) }

        criteria = Problem.for_apps(App.where(id: app.id))
        page = ProblemAggregationSorter.call(
          criteria: criteria,
          sort: "count",
          order: "desc",
          page: 1,
          per_page: 10,
        )

        expect(page.map { |d| d.object.id }).to(eq([high.id, mid.id, low.id]))
      end

      it "reports total_count and limits page size" do
        app = Fabricate(:app)
        problems = Array.new(3) { Fabricate(:problem, app: app) }
        problems.each { |p| Fabricate(:notice, problem: p) }

        criteria = Problem.for_apps(App.where(id: app.id))
        page = ProblemAggregationSorter.call(
          criteria: criteria,
          sort: "last_notice_at",
          order: "desc",
          page: 1,
          per_page: 2,
        )

        expect(page.size).to(eq(2))
        expect(page.total_count).to(eq(3))
      end
    end

    context "resolved" do
      it 'only finds resolved Problems' do
        resolved = Fabricate(:problem, resolved: true)
        unresolved = Fabricate(:problem, resolved: false)
        expect(Problem.resolved.all).to(include(resolved))
        expect(Problem.resolved.all).to_not(include(unresolved))
      end
    end

    context "unresolved" do
      it 'only finds unresolved Problems' do
        resolved = Fabricate(:problem, resolved: true)
        unresolved = Fabricate(:problem, resolved: false)
        expect(Problem.unresolved.all).to_not(include(resolved))
        expect(Problem.unresolved.all).to(include(unresolved))
      end
    end

    context "searching" do
      it 'finds the correct record' do
        app = Fabricate(:app, name: 'other')
        find = Fabricate(
          :problem,
          resolved: false,
          app: app,
          error_class: 'theErrorclass::other',
          message: "other",
          where: 'errorclass',
          environment: 'development',
        )
        Fabricate(
          :notice,
          problem: find,
          message: "other",
        )

        dont_find = Fabricate(:problem, resolved: false)
        Fabricate(:notice, problem: dont_find, message: 'todo', error_class: 'Batman')

        expect(Problem.search("theErrorClass").unresolved).to(include(find))
        expect(Problem.search("theErrorClass").unresolved).to_not(include(dont_find))
      end
      it 'find on where message' do
        problem = Fabricate(:problem, where: 'cyril')
        Fabricate(:notice, problem: problem)
        expect(Problem.search('cyril').entries).to(include(problem))
      end
      it 'finds with notice_id as argument' do
        app = Fabricate(:app)
        problem = Fabricate(:problem, app: app)
        notice = Fabricate(:notice, problem: problem, message: 'ERR 1')

        problem2 = Fabricate(:problem, where: 'cyril')
        expect(problem2).to_not(eq(problem))
        expect(Problem.search(notice.id).entries).to(eq([problem]))
      end
    end
  end

  context "notice counter cache" do
    before do
      @app = Fabricate(:app)
      @problem = Fabricate(:problem, app: @app)
    end

    it "#notices_count returns 0 by default" do
      expect(@problem.notices_count).to(eq(0))
    end

    it "adding a notice increases #notices_count by 1" do
      expect do
        Fabricate(:notice, problem: @problem, message: 'ERR 1')
      end.to(change(@problem.reload, :notices_count).from(0).to(1))
    end

    it "removing a notice decreases #notices_count by 1" do
      Fabricate(:notice, problem: @problem, message: 'ERR 1')
      expect do
        @problem.notices.first.destroy
        @problem.reload
      end.to(change(@problem, :notices_count).from(1).to(0))
    end
  end

  context "filtered" do
    before do
      @app1 = Fabricate(:app)
      @problem1 = Fabricate(:problem, app: @app1)

      @app2 = Fabricate(:app)
      @problem2 = Fabricate(:problem, app: @app2)

      @app3 = Fabricate(:app)
      @app3.update_attribute(:name, 'app3')

      @problem3 = Fabricate(:problem, app: @app3)
    end

    it "#filtered returns problems but excludes those attached to the specified apps" do
      expect(Problem.filtered("-app:'#{@app1.name}'")).to(include(@problem2))
      expect(Problem.filtered("-app:'#{@app1.name}'")).to_not(include(@problem1))

      filtered_results_with_two_exclusions = Problem.filtered("-app:'#{@app1.name}' -app:app3")
      expect(filtered_results_with_two_exclusions).to_not(include(@problem1))
      expect(filtered_results_with_two_exclusions).to(include(@problem2))
      expect(filtered_results_with_two_exclusions).to_not(include(@problem3))
    end

    it "#filtered does not explode if given a nil filter" do
      filtered_results = Problem.filtered(nil)
      expect(filtered_results).to(include(@problem1))
      expect(filtered_results).to(include(@problem2))
      expect(filtered_results).to(include(@problem3))
    end

    it "#filtered does nothing for unimplemented filter types" do
      filtered_results = Problem.filtered("filterthatdoesnotexist:hotapp")
      expect(filtered_results).to(include(@problem1))
      expect(filtered_results).to(include(@problem2))
      expect(filtered_results).to(include(@problem3))
    end
  end

  context "#app_name" do
    let!(:app) { Fabricate(:app) }
    let!(:problem) { Fabricate(:problem, app: app) }

    before { app.reload }

    it "is set when a problem is created" do
      assert_equal app.name, problem.app_name
    end

    it "is updated when an app is updated" do
      expect do
        app.update_attributes!(name: "Bar App")
        problem.reload
      end.to(change(problem, :app_name).to("Bar App"))
    end
  end

  context "#url" do
    subject { Fabricate(:problem) }

    it "uses the configured protocol" do
      allow(Errbit::Config).to(receive(:protocol).and_return("https"))

      expect(subject.url).to(eq("https://errbit.example.com/apps/#{subject.app.id}/problems/#{subject.id}"))
    end

    it "uses the configured host" do
      allow(Errbit::Config).to(receive(:host).and_return("memyselfandi.com"))

      expect(subject.url).to(eq("http://memyselfandi.com/apps/#{subject.app.id}/problems/#{subject.id}"))
    end

    it "uses the configured port" do
      allow(Errbit::Config).to(receive(:port).and_return(8123))

      expect(subject.url).to(eq("http://errbit.example.com:8123/apps/#{subject.app.id}/problems/#{subject.id}"))
    end
  end
end
