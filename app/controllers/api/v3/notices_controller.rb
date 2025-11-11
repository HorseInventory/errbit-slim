class Api::V3::NoticesController < ApplicationController
  VERSION_TOO_OLD = 'Notice for old app version ignored'.freeze
  UNKNOWN_API_KEY = 'Your API key is unknown'.freeze

  skip_before_action :authenticate_user!
  before_action :set_cors_headers
  respond_to :json

  def create
    return render(status: :ok, body: '') if request.method == 'OPTIONS'

    merged_params = merged_request_params
    validate_errors!(merged_params['errors'])

    report = AirbrakeApi::V3::NoticeParser.new(merged_params).report

    unless report.valid?
      return render(json: { error: report.errors }, status: :unprocessable_entity)
    end

    report.generate_notice!
    render(status: :created, json: { id: report.notice.id, url: report.problem.url })
  rescue AirbrakeApi::ParamsError => e
    Rails.logger.error(e.pretty_inspect)
    Rails.logger.error(e.backtrace.join("\n"))
    render(json: { error: 'Invalid request', details: e.pretty_inspect }, status: :bad_request)
  rescue StandardError => e
    Rails.logger.error(e.pretty_inspect)
    Rails.logger.error(e.backtrace.join("\n"))
    render(json: { error: 'Unexpected server error', details: e.pretty_inspect }, status: :internal_server_error)
  end

private

  def set_cors_headers
    response.headers['Access-Control-Allow-Origin'] = '*'
    response.headers['Access-Control-Allow-Headers'] = 'origin, content-type, accept'
  end

  def merged_request_params
    parsed_body = request.raw_post.present? ? JSON.parse(request.raw_post) : {}

    params.merge(parsed_body).tap do |p|
      p['key'] ||= request.headers['X-Airbrake-Token'] || authorization_token
    end
  end

  def validate_errors!(errors)
    return if errors.blank?

    errors.each_with_index do |error, index|
      missing_fields = ['message', 'backtrace'].select { |field| error[field].blank? }
      raise AirbrakeApi::ParamsError, "Error at index #{index}: Missing fields #{missing_fields.join(", ")}" unless missing_fields.empty?
    end
  end

  def authorization_token
    request.headers['Authorization'].to_s[/Bearer (.+)/, 1]
  end
end
