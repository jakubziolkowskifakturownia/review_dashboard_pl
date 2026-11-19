# Chipy list zadań z trackera (TrackerTask) przy PR-ach. Listy czytamy z cache —
# widok nigdy nie pyta trackera.
module TrackerListsHelper
  # `selected_ids` wyróżnia listy wybrane w filtrze — widać, czemu PR jest widoczny.
  def task_lists_tag(lists, selected_ids: [])
    return if lists.blank?

    tag.div(class: "task-lists") do
      safe_join(lists.map do |list|
        link_to list["name"], list["url"], target: "_blank", rel: "noopener", title: "lista zadań w trackerze",
                class: class_names("tasklist-chip", "tasklist-chip-selected" => selected_ids.include?(list["id"].to_s))
      end)
    end
  end

  # Parametry listy jako ukryte pola formularza — tablice (tasklist_ids) jako `name[]`.
  def hidden_list_params(params_hash)
    safe_join(params_hash.flat_map do |name, value|
      Array(value).map { |item| hidden_field_tag(value.is_a?(Array) ? "#{name}[]" : name, item, id: nil) }
    end)
  end

  # Pojedynczy review (wiersz z broadcastu, strona review) — bez gotowej mapy z kontrolera.
  def review_task_lists(review, lists_by_number = nil)
    number = review.task_scoped_id
    return [] unless number

    lists_by_number ? lists_by_number.fetch(number, []) : TrackerTask.find_by(project_id: review.project_id, number: number)&.lists.to_a
  end
end
