# Uzupełnia cache list zadań (TrackerTask) dla zadań z kolejki „czeka na Twoje
# review" i z review projektu. Tracker nie ma zbiorczego endpointu list — jeden
# request na zadanie — więc pytamy tylko o brakujące i nieświeże, kilka naraz.
# `force` (przycisk „Odśwież listy”, harmonogram poranny) pyta o wszystkie: zadanie
# przepięte do nowego cyklu inaczej czekałoby do końca STALE_AFTER.
class RefreshTrackerTasksJob < ApplicationJob
  THREADS = 4

  queue_as :default

  # Klik „Odśwież” w trakcie trwającego odświeżania nie dubluje requestów do trackera.
  limits_concurrency key: ->(project, **) { project.id }

  def perform(project, force: false, client: nil)
    return unless project.tracker_enabled?

    client ||= project.tracker_client
    numbers = task_numbers(project)
    unless force
      fresh = TrackerTask.where(project: project, number: numbers).reject(&:stale?).map(&:number)
      numbers -= fresh
    end
    return if numbers.empty?

    # HTTP w wątkach, zapis w wątku joba — wątki nie dotykają ActiveRecord.
    fetched = numbers.each_slice(THREADS).flat_map do |slice|
      slice.map { |number| Thread.new { [ number, fetch(client, number) ] } }.map(&:value)
    end
    now = Time.current
    rows = fetched.filter_map do |number, lists|
      next if lists.nil? # błąd trackera — zostają poprzednie dane

      { project_id: project.id, number: number, lists: lists, fetched_at: now, created_at: now, updated_at: now }
    end
    TrackerTask.upsert_all(rows, unique_by: %i[project_id number], update_only: %i[lists fetched_at updated_at]) if rows.any?
    BroadcastDashboardJob.perform_later
  end

  private

  # Tylko linki z prefiksu trackera: dla obcego linku TaskLink.number zgaduje
  # „ostatnią liczbę w adresie”, a o taki numer nie wolno pytać trackera.
  def task_numbers(project)
    pattern = "#{ActiveRecord::Base.sanitize_sql_like(project.task_url_prefix)}%"
    from_inbox = project.inbox_items.where("task_url LIKE ?", pattern).map(&:task_number)
    from_reviews = project.reviews.where("task_url LIKE ?", pattern).map(&:task_scoped_id)
    (from_inbox + from_reviews).compact.uniq
  end

  def fetch(client, number)
    client.task_lists(number)
  rescue IntumClient::Error => e
    Rails.logger.warn("[RefreshTrackerTasksJob] listy zadania ##{number}: #{e.message}")
    nil
  end
end
