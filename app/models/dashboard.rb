# Stan strony wejściowej policzony w jednym miejscu. Kontroler renderuje z niego
# pierwsze wejście, BroadcastDashboardJob — każde kolejne odświeżenie kolejek
# z tła. Dopóki partiale czytały ivary kontrolera, broadcast renderował je
# z samymi nilami, więc kolejki mogły się aktualizować tylko przez F5.
#
# Klasa jest czytelnikiem: NIC nie zleca i nic nie zapisuje. Efekty uboczne
# strony wejściowej (odświeżenie kolejki z GitHuba, sprawdzenie statusu PR-ów)
# zostają w kontrolerze — job broadcastu nie może ich odpalać w kółko.
class Dashboard
  attr_reader :main_project

  def initialize(main_project: Project.main)
    @main_project = main_project
  end

  def projects = @projects ||= Project.active.by_name

  # Widok pokazuje wyłącznie projekt główny — kolejki różnych projektów mieszały
  # się nie do odróżnienia.
  def inbox_items
    @inbox_items ||= all_inbox_items.select { |item| main_project.inbox_item_visible?(item) }
  end

  def hidden_inbox_count = all_inbox_items.size - inbox_items.size

  # Przełącznik „bez Odezwał się" ma sens, gdy w kolejce jest jakieś „odezwał się"
  # — albo gdy jest włączony (musi dać się go wyłączyć, nawet przy pustej grupie).
  def inbox_commented_filter?
    return false unless main_project

    main_project.inbox_hide_commented? || all_inbox_items.any? { |item| item.reason == "commented" }
  end

  # Labelki z kolejki plus te z filtra — zapisany filtr musi dać się zdjąć także wtedy,
  # gdy jego labelka zniknęła z kolejki (inaczej ukryłby PR-y bez przycisku do cofnięcia).
  def inbox_label_options
    return [] unless main_project

    (all_inbox_items.flat_map(&:pr_labels) + main_project.inbox_shown_labels + main_project.inbox_hidden_labels)
      .uniq.sort_by(&:downcase)
  end

  # Review dla tych PR-ów, żeby kafel wiedział, czy prowadzi do istniejącego review,
  # czy proponuje założenie nowego. Jedno zapytanie, nie jedno na kafel.
  def inbox_reviews
    @inbox_reviews ||= Review.where(project: main_project, pr_number: inbox_items.map(&:pr_number))
                             .index_by { |review| [ review.project_id, review.pr_number ] }
  end

  def inbox_checked_at = main_project&.inbox_checked_at

  # Listy zadań z trackera dla kafla (InboxItem albo Review) — jedna mapa na stronę.
  def tracker_lists_for(record)
    number = record.is_a?(InboxItem) ? record.task_number : record.task_scoped_id
    number ? tracker_lists_by_number.fetch(number, []) : []
  end

  # Opcje selektu „Lista zadań": listy z zadań PR-ów widocznych w kolejce projektu
  # głównego, z liczbą PR-ów. Wszystkich list trackera są setki, a większość byłaby
  # tu pusta. Zapisana lista zostaje w opcjach także z zerem — inaczej nie dałoby
  # się zobaczyć, co jest wybrane.
  def tasklist_options
    return [] unless main_project&.tracker_enabled?

    @tasklist_options ||= begin
      counts = Hash.new(0)
      names = {}
      inbox_items.each do |item|
        tracker_lists_for(item).each do |list|
          counts[list["id"].to_s] += 1
          names[list["id"].to_s] = list["name"]
        end
      end
      if (selected = main_project.inbox_tasklist_id).present? && !names.key?(selected)
        names[selected] = tracker_list_name(selected) || "lista ##{selected}"
      end
      names.map { |id, name| { "id" => id, "name" => name, "count" => counts[id] } }
           .sort_by { |option| option["name"].downcase }
    end
  end

  def selected_tasklist_id = main_project&.inbox_tasklist_id.presence

  # Wybrana lista nie chowa reszty, tylko ją spycha: PR spoza cyklu dalej czeka na mnie
  # w GitHubie. Bez wybranej listy wszystko jest „na liście".
  def inbox_items_on_list
    return inbox_items unless selected_tasklist_id

    inbox_items.select { |item| on_selected_list?(item) }
  end

  def inbox_items_off_list
    return [] unless selected_tasklist_id

    inbox_items.reject { |item| on_selected_list?(item) }
  end

  def tracker_lists_by_number
    @tracker_lists_by_number ||= TrackerTask.lists_by_number(main_project)
  end

  # Jeden PR = jedna karta. Review, którego PR wisi już w kolejce z GitHuba, nie wraca
  # niżej w drugiej sekcji: to ta sama robota opisana dwa razy, tylko innym zegarem
  # (sygnał z GitHuba vs ostatni ruch w dashboardzie). Kafel kolejki dowozi za to stan
  # review i następny krok — patrz projects/_inbox_item.
  def attention_reviews
    @attention_reviews ||= begin
      # Pełna kolejka, nie przefiltrowana: PR ukryty filtrem dalej czeka na mnie w GitHubie.
      in_inbox = all_inbox_items.map(&:pr_number).compact
      waiting.select { |r| r.status.in?(Review::ATTENTION_STATUSES) }
             .reject { |r| r.pr_number.present? && in_inbox.include?(r.pr_number) }
             .sort_by { |r| [ Review::ATTENTION_ORDER.index(r.status), r.updated_at ] }
    end
  end

  def in_progress_reviews
    @in_progress_reviews ||= waiting.select { |r| r.status.in?(Review::IN_PROGRESS_STATUSES) }
                                    .sort_by(&:updated_at).reverse
  end

  # Te same sygnały co na liście review, jednym zapytaniem: „reviewing" bez
  # pracującej sesji znaczy, że job stoi w kolejce workera, a weryfikacja uwag
  # (pending też) nie zmienia statusu review, więc kafel musi o niej wiedzieć sam.
  def running_review_ids
    @running_review_ids ||= active_runs.filter_map { |review_id, _kind, status| review_id if status == "running" }.uniq
  end

  def verifying_review_ids
    @verifying_review_ids ||= active_runs.filter_map { |review_id, kind, _status| review_id if kind == "verify_findings" }.uniq
  end

  # Review z projektu głównego, których dotyczy którakolwiek kolejka — jednym
  # zapytaniem, bo kolejność „Czeka na Ciebie" i tak sortuje się w Ruby (po
  # ATTENTION_ORDER, czego SQLite nie wyrazi bez CASE dłuższego niż ta klasa).
  # outward: selfreview to prywatna runda przed PR-em — jego wynik czeka na liście
  # projektu, a nie w kolejkach „co teraz kliknąć" na stronie wejściowej.
  def waiting
    @waiting ||= Review.outward
                       .where(project: main_project,
                              status: Review::ATTENTION_STATUSES + Review::IN_PROGRESS_STATUSES)
                       .includes(:project, :findings).to_a
  end

  private

  def on_selected_list?(item)
    tracker_lists_for(item).any? { |list| list["id"].to_s == selected_tasklist_id }
  end

  def tracker_list_name(id)
    tracker_lists_by_number.each_value { |lists| lists.each { |list| return list["name"] if list["id"].to_s == id } }
    nil
  end

  def all_inbox_items
    @all_inbox_items ||= InboxItem.where(project: main_project).includes(:project).by_urgency.to_a
  end

  def active_runs
    @active_runs ||= ClaudeRun.where(status: "running")
                              .or(ClaudeRun.where(kind: "verify_findings", status: "pending"))
                              .pluck(:review_id, :kind, :status)
  end
end
