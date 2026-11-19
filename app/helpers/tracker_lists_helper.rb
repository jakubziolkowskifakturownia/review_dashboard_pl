# Chipy list zadań z trackera (TrackerTask) przy PR-ach. Listy czytamy z cache —
# widok nigdy nie pyta trackera.
module TrackerListsHelper
  # `selected_id` wyróżnia listę wybraną w filtrze — widać, czemu PR jest na górze.
  def task_lists_tag(lists, selected_id: nil)
    return if lists.blank?

    tag.div(class: "task-lists") do
      safe_join(lists.map do |list|
        link_to list["name"], list["url"], target: "_blank", rel: "noopener", title: "lista zadań w trackerze",
                class: class_names("tasklist-chip", "tasklist-chip-selected" => list["id"].to_s == selected_id.to_s)
      end)
    end
  end

  # Pojedynczy review (wiersz z broadcastu, strona review) — bez gotowej mapy z kontrolera.
  def review_task_lists(review, lists_by_number = nil)
    number = review.task_scoped_id
    return [] unless number

    lists_by_number ? lists_by_number.fetch(number, []) : TrackerTask.find_by(project_id: review.project_id, number: number)&.lists.to_a
  end
end
