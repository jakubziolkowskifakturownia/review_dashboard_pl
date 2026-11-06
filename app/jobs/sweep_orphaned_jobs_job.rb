# Wejście harmonogramu (config/recurring.yml) dla OrphanedJobsSweep.
class SweepOrphanedJobsJob < ApplicationJob
  queue_as :default

  def perform
    OrphanedJobsSweep.call
  end
end
