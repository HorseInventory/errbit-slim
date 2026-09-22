describe "problems/show.html.haml", type: 'view' do
  let(:problem) { Fabricate(:problem_with_notices) }
  let(:app) { AppDecorator.new(problem.app) }

  before do
    params[:app_id] = app.id
    allow(view).to(receive(:app).and_return(app))
    allow(view).to(receive(:problem).and_return(problem))

    assign :notices, problem.notices.page(1).per(1)
    assign :notice, NoticeDecorator.new(problem.notices.first)
    assign :all_notices, problem.notices.reverse_ordered.page(1).per(50)

    allow(controller).to(receive(:current_user).and_return(Fabricate(:user)))
  end

  describe "content_for :action_bar" do
    def action_bar
      view.content_for(:action_bar)
    end

    it "should confirm the 'resolve' link by default" do
      render
      expect(action_bar).to(have_selector(
        format(
          'a.resolve[data-confirm="%s"]',
          I18n.t('problems.confirm.resolve_one'),
        ),
      ))
    end

    it "should confirm the 'resolve' link if configuration is unset" do
      allow(Errbit::Config).to(receive(:confirm_err_actions).and_return(nil))
      render
      expect(action_bar).to(have_selector(
        format(
          'a.resolve[data-confirm="%s"]',
          I18n.t('problems.confirm.resolve_one'),
        ),
      ))
    end

    it "should not confirm the 'resolve' link if configured not to" do
      allow(Errbit::Config).to(receive(:confirm_err_actions).and_return(false))
      render
      expect(action_bar).not_to(have_selector('a.resolve[data-confirm=""]'))
    end

    it "should link 'up' to HTTP_REFERER if is set" do
      url = 'http://localhost:3000/problems'
      controller.request.env['HTTP_REFERER'] = url
      render
      expect(action_bar).to(have_selector("span a.up[href='#{url}']", text: 'up'))
    end

    it "should link 'up' to app_problems_path if HTTP_REFERER isn't set'" do
      controller.request.env['HTTP_REFERER'] = nil

      allow(view).to(receive(:problem).and_return(problem))
      allow(view).to(receive(:app).and_return(problem.app))
      render

      expect(action_bar).to(have_selector("span a.up[href='#{app_problems_path(problem.app)}']", text: 'up'))
    end
  end
end
