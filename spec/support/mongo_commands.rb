module MongoCommands
  class Recorder
    attr_reader :commands

    def initialize
      @commands = []
    end

    def started(event)
      commands << event.command
    end

    def succeeded(event); end
    def failed(event); end
  end

  def record_mongo_commands
    recorder = Recorder.new
    client = Mongoid.default_client
    client.subscribe(Mongo::Monitoring::COMMAND, recorder)
    yield
    recorder.commands
  ensure
    client.unsubscribe(Mongo::Monitoring::COMMAND, recorder)
  end
end

RSpec.configure do |config|
  config.include(MongoCommands)
end
