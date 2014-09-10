module RMXFirebase

  SCHEDULER = RACScheduler.scheduler

  def self.rac_schedulerFor(scheduler)
    case scheduler
    when nil, :main
      RACScheduler.mainThreadScheduler
    when :async
      SCHEDULER
    when RACScheduler
      scheduler
    else
      raise "unknown scheduler: #{scheduler.inspect}"
    end
  end

end
