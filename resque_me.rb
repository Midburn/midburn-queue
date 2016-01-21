# environment space
require "sinatra"
require "dotenv"; Dotenv.load

# application space
require "redis"
require "resque"
require "./worker.rb"

TIER_SIZE = 5

class ResqueMe < Sinatra::Base

  def log_request
    logger.info "======== GOT REQUEST ========\n#{request.body.read}\n\n======== GOT REQUEST ========\n"
  end

  def get_params
    JSON.parse(request.body.read)
  end

	get '/' do
    redirect "http://midburn.org"
	end

  get '/redis' do
    begin
      Resque.info
      "OK"
    rescue Exception => e
      "Failed"
    end
  end

  post '/big-reset' do
    payload = get_params
    if payload["secret_token"] == ENV["admin_secret_token"]
      logger.info "Performing big reset. Removing all tasks from all queues!"
      queues = Resque.queues
      queues.each do |queue_name|
        logger.info "Clearing #{queue_name}..."
        Resque.remove_queue "#{queue_name}"
        Resque.redis.del "queue:#{queue_name}"
      end
      
      logger.info "Clearing delayed..." # in case of scheduler - doesn't break if no scheduler module is installed
      Resque.redis.keys("delayed:*").each do |key|
        Resque.redis.del "#{key}"
      end
      Resque.redis.del "delayed_queue_schedule"
      
      logger.info "Clearing stats..."
      Resque.redis.set "stat:failed", 0 
      Resque.redis.set "stat:processed", 0
      logger.info "Done."
    else
      logger.error "tried to reset DB with wrong admin secret token!"
    end

  end

  post '/enqueue' do
    payload = get_params
    order_json = %{{"firstname":"#{payload["firstname"]}","lastname":"#{payload["lastname"]}","email":"#{payload["email"]}"}}

    tier_number = (Resque.info[:pending] + Resque.info[:processed]).div TIER_SIZE
    Resque.enqueue(eval("OrderTier_#{tier_number}"), order_json)
  end

end