# frozen_string_literal: true

require_relative 'management'
class App < Sinatra::Base
  helpers Sinatra::CustomLogger
  include HookDirection
  attr_accessor :params

  def initialize
    @version = '0.1.3'
    super
  end

  before do
    body = request.body.read
    @redis = Redis.new(path: 'tmp/redis/redis.sock')
    @object = GithubResponceObjects.new(JSON.parse(body)) unless body == ''
    @params = JSON.parse(body) unless body == ''
  end

  configure do
    logger = Logger.new($stdout)
    logger.level = Logger::DEBUG if development?
    set :logger, logger
  end

  get '/' do
    @secret_token = !ENV['SECRET_TOKEN'].nil?
    @commits_count = @redis.lrange('github_warden_action', 0, -1).size
    @redis_ping = @redis.ping == 'PONG'
    erb :index
  end

  post '/' do
    request.body.rewind
    payload_body = request.body.read
    verify_signature(payload_body)
    if @object.commits
      result = find_action(@object)
      @redis.lpush 'github_warden_action', result.to_json
      logger.info "-> New result: #{result.to_json}"
      result.to_json
    else
      nil.to_json
    end
  end

  def verify_signature(payload_body)
    halt 500, { errors: ['No HTTP_X_HUB_SIGNATURE'] }.to_json unless request.env['HTTP_X_HUB_SIGNATURE']
    halt 500, { errors: ['No SECRET_TOKEN'] }.to_json unless ENV['SECRET_TOKEN']
    signature = "sha1=#{OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['SECRET_TOKEN'], payload_body)}"
    halt 500, { errors: ['Wrong signatures'] }.to_json unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
  end
end
