require "test_helper"

# Chipy list zadań z trackera przy PR-ach — wszędzie, gdzie PR się pokazuje.
class TrackerListsDisplayTest < ActionDispatch::IntegrationTest
  PREFIX = "https://tracker.example.com/organize/tasks/".freeze
  CYKL = { "id" => "101", "name" => "Cykl A", "url" => "https://tracker.example.com/organize/tasklists/101" }.freeze

  setup do
    @project = projects(:webapp)
    @project.update!(main_at: Time.current, task_url_prefix: PREFIX, intum_api_token: "tajny")
    TrackerTask.create!(project: @project, number: "111", lists: [ CYKL ], fetched_at: Time.current)
  end

  test "kafel kolejki pokazuje listy zadania PR-a" do
    inbox_items(:requested).update!(task_url: "#{PREFIX}111")

    get root_path

    assert_select "#inbox_pr_9001 .tasklist-chip", text: "Cykl A"
    assert_select "#inbox_pr_9001 .tasklist-chip[href=?]", CYKL["url"]
  end

  test "PR bez zadania — brak chipów" do
    get root_path

    assert_select "#inbox_pr_9001"
    assert_select "#inbox_pr_9001 .tasklist-chip", 0
  end

  test "kafel review w kolejce pokazuje listy" do
    review = Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/77",
                            task_url: "#{PREFIX}111", status: "ready")

    get root_path

    assert_select "#review_queue_#{review.id} .tasklist-chip", text: "Cykl A"
  end

  test "wiersz listy review i strona review pokazują listy" do
    review = Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/78", task_url: "#{PREFIX}t/111")

    get project_reviews_path(@project)
    assert_select "#review_row_#{review.id} .tasklist-chip", text: "Cykl A"

    get review_path(review)
    assert_select ".tasklist-chip", text: "Cykl A"
  end

  test "selekt list nad kolejką; wybór zapisuje listę i przerysowuje dashboard" do
    inbox_items(:requested).update!(task_url: "#{PREFIX}111")

    get root_path
    assert_select "#inbox_tasklist_filter option[data-id=?]", "101"

    assert_enqueued_with(job: BroadcastDashboardJob) do
      post select_inbox_tasklist_projects_path, params: { tasklist_id: "101" }
    end
    assert_equal "101", @project.reload.inbox_tasklist_id

    get root_path
    assert_select "#inbox_pr_9001 .tasklist-chip-selected", text: "Cykl A"
    assert_select ".qdivider", text: /spoza wybranej listy/

    post select_inbox_tasklist_projects_path, params: { tasklist_id: "" }
    assert_nil @project.reload.inbox_tasklist_id
  end

  test "projekt bez trackera — brak selektu" do
    @project.update_columns(task_url_prefix: nil)

    get root_path

    assert_select "#inbox_tasklist_filter", 0
  end

  test "Odśwież listy zleca pobranie wszystkiego od nowa" do
    assert_enqueued_with(job: RefreshTrackerTasksJob, args: [ @project, { force: true } ]) do
      post refresh_tracker_lists_project_path(@project)
    end
  end

  test "indeks review: wybrana lista na górze, potem reszta w wybranym sortowaniu" do
    TrackerTask.create!(project: @project, number: "222", lists: [ { "id" => "102", "name" => "Backlog B", "url" => "x" } ])
    old_on_list = Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/80",
                                 task_url: "#{PREFIX}111", created_at: 3.days.ago)
    newest = Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/81", task_url: "#{PREFIX}222")

    get project_reviews_path(@project, tasklist_id: "101")

    rows = css_select("#reviews tbody tr").map { |row| row["id"] }
    assert_equal "review_row_#{old_on_list.id}", rows.first
    assert_operator rows.index("review_row_#{newest.id}"), :>, 0
    assert_select "#reviews_tasklist_filter option[data-id=?]", "101"
    assert_select "#reviews_tasklist_filter option[data-id=?]", "102"
  end

  test "indeks review: opcje tylko z review tego projektu" do
    other = projects(:dashboard)
    other.update!(task_url_prefix: PREFIX, intum_api_token: "tajny")
    TrackerTask.create!(project: other, number: "111", lists: [ { "id" => "999", "name" => "Cudza", "url" => "x" } ])
    Review.create!(project: other, pr_url: "https://github.com/example/dashboard/pull/1", task_url: "#{PREFIX}111")
    Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/82", task_url: "#{PREFIX}111")

    get project_reviews_path(@project)

    assert_select "#reviews_tasklist_filter option[data-id=?]", "101"
    assert_select "#reviews_tasklist_filter option[data-id=?]", "999", count: 0
  end

  test "indeks review: wybrana lista zostaje w filtrze statusu" do
    Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/83", task_url: "#{PREFIX}111")

    get project_reviews_path(@project, tasklist_id: "101")

    assert_select "form.filter input[type=hidden][name=tasklist_id][value=?]", "101"
  end
end
