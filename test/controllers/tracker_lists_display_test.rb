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
end
