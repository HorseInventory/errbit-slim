describe ProblemsController, type: 'controller' do
  it_requires_authentication for:    {
                               index: :get, show: :get, resolve: :put, search: :get,
                             },
    params: { app_id: 'dummyid', id: 'dummyid' }

  let(:app) { Fabricate(:app) }
  let(:user) { Fabricate(:user) }
  let(:problem) { Fabricate(:problem, app: app, environment: "production") }

  describe "GET /problems" do
    before(:each) do
      sign_in user
    end

    context "pagination" do
      before(:each) do
        35.times { Fabricate :problem }
      end

      it "should have default per_page value for user" do
        get :index
        expect(controller.problems.to_a.size).to(eq(User::PER_PAGE))
      end

      it "should be able to override default per_page value" do
        user.update_attribute(:per_page, 10)
        get :index
        expect(controller.problems.to_a.size).to(eq(10))
      end
    end

    context 'with environment filters' do
      before(:each) do
        environments = ['production', 'test', 'development', 'staging']
        environments.each do |env|
          6.times do
            prob = Fabricate(:problem, app: app, environment: env)
            Fabricate(:notice, problem: prob, server_environment: { 'environment-name' => env })
          end
        end
      end

      context 'no params' do
        it 'shows problems for all environments' do
          get :index
          expect(controller.problems.size).to(eq(24))
        end
      end

      context 'environment production' do
        it 'shows problems for just production' do
          get :index, params: { environment: 'production' }
          expect(controller.problems.size).to(eq(6))
        end
      end

      context 'environment staging' do
        it 'shows problems for just staging' do
          get :index, params: { environment: 'staging' }
          expect(controller.problems.size).to(eq(6))
        end
      end

      context 'environment development' do
        it 'shows problems for just development' do
          get :index, params: { environment: 'development' }
          expect(controller.problems.size).to(eq(6))
        end
      end

      context 'environment test' do
        it 'shows problems for just test' do
          get :index, params: { environment: 'test' }
          expect(controller.problems.size).to(eq(6))
        end
      end
    end
  end

  describe "GET /problems with all_errs" do
    it "includes resolved problems in latest-notice order" do
      sign_in user
      resolved_problem = Fabricate(:problem, app: app, resolved: true)
      Fabricate(:notice, problem: problem, created_at: 2.days.ago)
      Fabricate(:notice, problem: resolved_problem, created_at: 1.day.ago)

      get :index, params: { all_errs: true }

      expect(controller.problems.map(&:id)).to(eq([resolved_problem.id, problem.id]))
    end
  end

  describe "GET /problems/search" do
    before do
      sign_in user
      @app      = Fabricate(:app)
      @problem1 = Fabricate(:problem, app: @app, message: "Most important")
      @problem2 = Fabricate(:problem, app: @app, message: "Very very important")
    end

    it "renders successfully" do
      get :search
      expect(response).to(be_successful)
    end

    it "renders index template" do
      get :search
      expect(response).to(render_template('problems/index'))
    end

    it "searches problems for given string" do
      get :search, params: { search: "\"Most important\"" }
      expect(controller.problems).to(include(@problem1))
      expect(controller.problems).to_not(include(@problem2))
    end

    it "works when given string is empty" do
      get :search, params: { search: "" }
      expect(controller.problems).to(include(@problem1))
      expect(controller.problems).to(include(@problem2))
    end
  end

  # you do not need an app id, strictly speaking, to find
  # a problem, and if your metrics system does not happen
  # to know the app id, but does know the problem id,
  # it can be handy to have a way to link in to errbit.
  describe "GET /problems/:id" do
    before do
      sign_in user
    end

    it "should redirect to the standard problems page" do
      expect(get: problem_path(problem)).to(route_to(
        controller: 'problems', action: 'show_by_id', id: problem.id.to_s,
      ))
      get :show_by_id, params: { id: problem.id.to_s }
      expect(response).to(redirect_to(app_problem_path(app, problem.id)))
    end
  end

  describe "GET /apps/:app_id/problems/:id" do
    before do
      sign_in user
    end

    it "finds the app" do
      problem = Fabricate(:problem, app: app)
      get :show, params: { app_id: app.id, id: problem.id }
      expect(controller.app).to(eq(app))
    end

    it "finds the problem" do
      problem = Fabricate(:problem, app: app)
      get :show, params: { app_id: app.id, id: problem.id }
      expect(controller.problem).to(eq(problem))
    end

    it "successfully render page" do
      problem = Fabricate(:problem, app: app)
      get :show, params: { app_id: app.id, id: problem.id }
      expect(response).to(be_successful)
    end

    context "when rendering views" do
      render_views

      it "successfully renders the view even when there are no notices attached to the problem" do
        problem = Fabricate(:problem, app: app)
        expect(problem.notices).to(be_empty)
        get :show, params: { app_id: app.id, id: problem.id }
        expect(response).to(be_successful)
      end

      it 'loads only occurrence table fields and calculates statistics once' do
        problem = Fabricate(:problem, app: app)
        notice = Fabricate(:notice, problem: problem, request: {
          'component' => 'orders', 'action' => 'create', 'params' => { 'large' => 'x' * 100_000 },
        })

        commands = record_mongo_commands do
          get(:show, params: { app_id: app.id, id: problem.id })
        end

        expect(response).to(be_successful)
        table_notice = assigns(:all_notices).first
        expect(table_notice.request).to(eq('component' => 'orders', 'action' => 'create'))
        expect(assigns(:notice).request.fetch('params')).to(eq('large' => 'x' * 100_000))
        expect(response.body).to(include('orders#create', "notice_id=#{notice.id}"))
        expect(commands.count { |command| command['aggregate'] == 'notices' }).to(eq(1))
        full_notice_reads = commands.select { |command| command['find'] == 'notices' && !command.key?('projection') }
        expect(full_notice_reads.size).to(eq(1))
      end

      it 'paginates the occurrence table without fetching the full occurrence history' do
        problem = Fabricate(:problem, app: app)
        backtrace = Fabricate(:backtrace)
        notices = Array.new(51) { Fabricate(:notice, problem: problem, backtrace: backtrace) }

        get :show, params: { app_id: app.id, id: problem.id, page: 2 }

        expect(assigns(:all_notices).map(&:id)).to(eq([notices.first.id]))
        expect(assigns(:all_notices).total_count).to(eq(51))
        expect(assigns(:notices).first.id).to(eq(notices.last.id))
      end

      it 'renders compressed occurrences in the table and as the selected occurrence' do
        problem = Fabricate(:problem, app: app)
        notice = Fabricate(:notice, problem: problem)
        Notice.collection.find(_id: notice.id).update_one('$set' => {
          compressed: true, server_environment: {}, request: nil, notifier: {}, error_class: nil, backtrace_id: nil,
        })

        get :show, params: { app_id: app.id, id: problem.id, notice_id: notice.id }

        expect(response).to(be_successful)
        expect(assigns(:all_notices).first.where).to(eq(''))
        expect(assigns(:all_notices).total_count).to(eq(1))
        expect(assigns(:notice).backtrace).to(be_nil)
      end
    end

    context 'pagination' do
      let(:problems) do
        Fabricate.times(3, :problem_with_notices, app: app)
      end

      it "paginates the notices 1 at a time, starting with the most recent" do
        problem = problems.first
        notices = problem.notices
        get(:show, params: { app_id: app.id, id: problem.id })
        expect(assigns(:notices).entries.count).to(eq(1))
        expect(assigns(:notices)).to(include(notices.last))
      end

      it "paginates the notices 1 at a time, based on the notice param" do
        problem = problems.last
        notices = problem.notices
        get(:show, params: { app_id: app.id, id: problem.id, notice: 3 })
        expect(assigns(:notices).entries.count).to(eq(1))
        expect(assigns(:notices)).to(include(notices.first))
      end
    end
  end

  describe "PUT /apps/:app_id/problems/:id/resolve" do
    before do
      sign_in user

      @problem = Fabricate(:problem)
    end

    it 'finds the app and the problem' do
      put :resolve, params: { app_id: @problem.app.id, id: @problem.id }
      expect(controller.app).to(eq(@problem.app))
      expect(controller.problem).to(eq(@problem))
    end

    it "should resolve the issue" do
      put :resolve, params: { app_id: @problem.app.id, id: @problem.id }
      expect(@problem.reload.resolved).to(be(true))
    end

    it "should display a message" do
      put :resolve, params: { app_id: @problem.app.id, id: @problem.id }
      expect(request.flash[:success]).to(match(/Great news/))
    end

    it "should redirect to the app page" do
      request.env["HTTP_REFERER"] = app_path(@problem.app)
      put :resolve, params: { app_id: @problem.app.id, id: @problem.id }
      expect(response).to(redirect_to(app_path(@problem.app)))
    end

    it "should redirect back to problems page" do
      request.env["HTTP_REFERER"] = problems_path
      put :resolve, params: { app_id: @problem.app.id, id: @problem.id }
      expect(response).to(redirect_to(problems_path))
    end
  end

  describe "Bulk Actions" do
    before(:each) do
      sign_in user
      @problem1 = Fabricate(:problem, resolved: true)
      @problem2 = Fabricate(:problem, resolved: false)
    end

    context "POST /problems/merge_several" do
      it "should require at least two problems" do
        post :merge_several, params: { problems: [@problem1.id.to_s] }
        expect(request.flash[:notice]).to(eql(I18n.t('controllers.problems.flash.need_two_errors_merge')))
      end

      it "should merge the problems" do
        expect(ProblemMerge).to(receive(:new).and_return(double(merge: true)))
        post :merge_several, params: { problems: [@problem1.id.to_s, @problem2.id.to_s] }
      end
    end

    context "POST /problems/resolve_several" do
      it "should require at least one problem" do
        post :resolve_several, params: { problems: [] }
        expect(request.flash[:notice]).to(eql(I18n.t('controllers.problems.flash.no_select_problem')))
      end

      it "should resolve the issue" do
        post :resolve_several, params: { problems: [@problem2.id.to_s] }
        expect(@problem2.reload.resolved?).to(eq(true))
      end

      it "should display a message about 1 err" do
        post :resolve_several, params: { problems: [@problem2.id.to_s] }
        expect(flash[:success]).to(match(/1 error has been resolved/))
      end

      it "should display a message about 2 errs" do
        post :resolve_several, params: { problems: [@problem1.id.to_s, @problem2.id.to_s] }
        expect(flash[:success]).to(match(/2 errors have been resolved/))
        expect(controller.selected_problems).to(eq([@problem1, @problem2]))
      end
    end

    context "POST /problems/unresolve_several" do
      it "should require at least one problem" do
        post :unresolve_several, params: { problems: [] }
        expect(request.flash[:notice]).to(eql(I18n.t('controllers.problems.flash.no_select_problem')))
      end

      it "should unresolve the issue" do
        post :unresolve_several, params: { problems: [@problem1.id.to_s] }
        expect(@problem1.reload.resolved?).to(eq(false))
      end
    end

    context "POST /problems/destroy_several" do
      it "should delete the problems" do
        expect do
          post(:destroy_several, params: { problems: [@problem1.id.to_s] })
        end.to(change(Problem, :count).by(-1))
      end
    end

    describe "POST /apps/:app_id/problems/destroy_all" do
      before do
        sign_in user
        @app      = Fabricate(:app)
        @problem1 = Fabricate(:problem, app: @app)
        @problem2 = Fabricate(:problem, app: @app)
      end

      it "destroys all problems" do
        expect do
          post(:destroy_all, params: { app_id: @app.id })
        end.to(change(Problem, :count).by(-2))
        expect(controller.app).to(eq(@app))
      end

      it "should display a message" do
        put :destroy_all, params: { app_id: @app.id }
        expect(request.flash[:success]).to(match(/be deleted/))
      end

      it "should redirect back to the app page" do
        request.env["HTTP_REFERER"] = edit_app_path(@app)
        put :destroy_all, params: { app_id: @app.id }
        expect(response).to(redirect_to(edit_app_path(@app)))
      end
    end
  end
end
