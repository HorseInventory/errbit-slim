class ProblemsController < ApplicationController
  include ProblemsSearcher
  include ProblemSorting

  before_action :need_selected_problem, only: [
    :resolve_several, :unresolve_several,
  ]

  expose(:app_scope) do
    params[:app_id] ? App.where(_id: params[:app_id]) : App.all
  end

  expose(:app) do
    AppDecorator.new(app_scope.find(params[:app_id]))
  end

  expose(:problem) do
    ProblemDecorator.new(app.problems.find(params[:id]))
  end

  expose(:all_errs) do
    params[:all_errs]
  end

  expose(:filter) do
    params[:filter]
  end

  expose(:params_environment) do
    params[:environment]
  end

  # to use with_app_exclusions, hit a path like /problems?filter=-app:noisy_app%20-app:another_noisy_app
  # it would be possible to add a really fancy UI for it at some point, but for now, it's really
  # useful if there are noisy apps that you want to ignore.
  expose(:problems) do
    finder = Problem.
      for_apps(app_scope).
      in_env(params_environment).
      filtered(filter).
      all_else_unresolved(all_errs)

    finder = finder.search(params[:search]) if params[:search].present?

    sort_and_paginate_problems(finder, params_sort, params_order, params[:page], current_user.per_page)
  end

  def index
    query = {}

    if params.key?(:start_date) && params.key?(:end_date)
      start_date = Time.parse(params[:start_date]).utc
      end_date = Time.parse(params[:end_date]).utc
      query = { :first_notice_at => { "$lte" => end_date }, "$or" => [{ resolved_at: nil }, { resolved_at: { "$gte" => start_date } }] }
    end

    @problems = Problem.where(query)

    respond_to do |format|
      format.json { render(json: @problems) }
      format.html
    end
  end

  def show
    notice =
      if params[:notice_id]
        problem.object.notices.find(params[:notice_id])
      else
        @notices = paginate_notices(problem.object.notices, params[:notice], 1)
        @notices.first
      end
    @notice = notice ? NoticeDecorator.new(notice) : nil
    @all_notices = paginate_notices(
      problem.object.notices.only(:created_at, :error_class, :message, :problem_id, 'request.component', 'request.action'),
      params[:page],
      50,
    )

    respond_to do |format|
      format.html
      format.js
    end
  end

  def show_by_id
    problem = Problem.find(params[:id])
    redirect_to(app_problem_path(problem.app, problem))
  end

  def resolve
    problem.resolve!

    flash[:success] = t('.the_error_has_been_resolved')

    redirect_back(fallback_location: root_path)
  end

  def destroy
    ProblemDestroy.new(app.problems.where(id: problem.id)).execute

    flash[:success] = t('.the_error_has_been_deleted')

    redirect_to app_problems_path(app)
  end

  def resolve_several
    selected_problems.each(&:resolve!)

    flash[:success] = "Great news everyone! #{I18n.t(:n_errs_have, count: selected_problems.count)} #{I18n.t("n_errs_have.been_resolved")}."

    redirect_back(fallback_location: root_path)
  end

  def unresolve_several
    selected_problems.each(&:unresolve!)

    flash[:success] = "#{I18n.t(:n_errs_have, count: selected_problems.count)} #{I18n.t("n_errs_have.been_unresolved")}."

    redirect_back(fallback_location: root_path)
  end

  def merge_several
    if selected_problems.length < 2
      flash[:notice] = I18n.t('controllers.problems.flash.need_two_errors_merge')
    else
      ProblemMerge.new(selected_problems).merge

      flash[:notice] = I18n.t('controllers.problems.flash.merge_several.success', nb: selected_problems.count)
    end

    redirect_back(fallback_location: root_path)
  end

  def destroy_several
    DestroyProblemsByIdJob.perform_later(selected_problems_ids)

    flash[:notice] = "#{I18n.t(:n_errs, count: selected_problems.size)} #{I18n.t("n_errs.will_be_deleted")}."

    redirect_back(fallback_location: root_path)
  end

  def destroy_all
    DestroyProblemsByAppJob.perform_later(app.id)

    flash[:success] = "#{I18n.t(:n_errs, count: app.problems.count)} #{I18n.t("n_errs.will_be_deleted")}."

    redirect_back(fallback_location: root_path)
  end

  def search
    respond_to do |format|
      format.html { render(:index) }
      format.js
    end
  end

private

  def paginate_notices(notices, page, per_page)
    rows = notices.reverse_ordered.page(page).per(per_page).to_a
    Kaminari.paginate_array(rows, total_count: problem.notices_count).page(page).per(per_page)
  end

  def need_selected_problem
    return if err_ids.any?

    flash[:notice] = I18n.t('controllers.problems.flash.no_select_problem')

    redirect_back(fallback_location: root_path)
  end
end
