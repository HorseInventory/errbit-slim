class AppsController < ApplicationController
  include ProblemsSearcher
  include ProblemSorting

  before_action :require_admin!, except: [:index, :show, :search]
  before_action :parse_email_at_notices_or_set_default, only: [:create, :update]

  expose(:app_scope) do
    params[:search].present? ? App.search(params[:search]) : App.all
  end

  expose(:apps) do
    app_scope.to_a.sort.map { |app| AppDecorator.new(app) }
  end

  expose(:app)

  expose(:app_decorate) do
    AppDecorator.new(app)
  end

  expose(:all_errs) do
    params[:all_errs].present?
  end

  expose(:problems) do
    pr = app.problems
    pr = pr.unresolved unless all_errs
    pr = pr.in_env(params[:environment])

    sort_and_paginate_problems(pr, params_sort, params_order, params[:page], current_user.per_page)
  end

  def index; end

  def show
    app
  end

  def new
    plug_params(app)
  end

  def create
    if app.save
      redirect_to app_url(app), flash: { success: I18n.t('controllers.apps.flash.create.success') }
    else
      flash.now[:error] = I18n.t('controllers.apps.flash.create.error')
      render :new
    end
  end

  def update
    app.update(app_params)

    if app.save
      redirect_to app_url(app), flash: { success: I18n.t('controllers.apps.flash.update.success') }
    else
      flash.now[:error] = I18n.t('controllers.apps.flash.update.error')
      render :edit
    end
  end

  def edit
    plug_params(app)
  end

  def destroy
    if app.destroy
      redirect_to apps_url, flash: { success: I18n.t('controllers.apps.flash.destroy.success') }
    else
      flash.now[:error] = I18n.t('controllers.apps.flash.destroy.error')
      render :show
    end
  end

  def regenerate_api_key
    app.regenerate_api_key!
    redirect_to edit_app_path(app)
  end

  def search
    respond_to do |format|
      format.html { render :index }
      format.js
    end
  end

private

  def plug_params(app)
    app.copy_attributes_from(params[:copy_attributes_from]) if params[:copy_attributes_from]
  end

  # email_at_notices is edited as a string, and stored as an array.
  def parse_email_at_notices_or_set_default
    return if params[:app].blank?

    val = params[:app][:email_at_notices]
    return if val.blank?

    # Sanitize negative values, split on comma,
    # strip, parse as integer, remove all '0's.
    # If empty, set as default and show an error message.
    email_at_notices = val.
      gsub(/-\d+/, "").
      split(",").
      map { |v| v.strip.to_i }.
      reject { |v| v == 0 }

    if email_at_notices.any?
      params[:app][:email_at_notices] = email_at_notices
    else
      default_array = params[:app][:email_at_notices] = Errbit::Config.email_at_notices
      flash[:error] = "Couldn't parse your notification frequency. Value was reset to default (#{default_array.join(', ')})."
    end
  end

  def app_params
    params.require(:app).permit!
  end
end
