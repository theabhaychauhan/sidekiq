class SomeJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    puts "What's up?!?!"
    # Do something later
  end
end
