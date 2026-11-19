# Poranne odświeżenie list zadań (config/recurring.yml): przez noc zadania
# przechodzą do nowego cyklu, a nowe listy powstają — rano mają być aktualne.
class RefreshAllTrackerTasksJob < ApplicationJob
  queue_as :default

  def perform
    Project.active.select(&:tracker_enabled?).each do |project|
      RefreshTrackerTasksJob.perform_later(project, force: true)
    end
  end
end
