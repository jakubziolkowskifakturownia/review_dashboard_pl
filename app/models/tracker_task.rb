# Listy zadań (cykl, backlog, incydent…), na których leży zadanie z trackera —
# per projekt, po numerze z adresu zadania. Tylko cache: zapisuje go wyłącznie
# RefreshTrackerTasksJob, widoki czytają przez `lists_by_number`.
class TrackerTask < ApplicationRecord
  # Zadania bywają przepinane do nowego cyklu — po tym czasie pobieramy je od nowa.
  STALE_AFTER = 6.hours

  belongs_to :project

  validates :number, presence: true, uniqueness: { scope: :project_id }

  # Jedno zapytanie na stronę zamiast jednego na kafel.
  def self.lists_by_number(project)
    return {} unless project

    where(project: project).pluck(:number, :lists).to_h
  end

  def stale? = fetched_at.nil? || fetched_at < STALE_AFTER.ago
end
