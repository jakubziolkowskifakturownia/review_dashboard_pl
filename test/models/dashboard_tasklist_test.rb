require "test_helper"

# Wybór listy zadań w kolejce „Czeka na Twoje review" (Dashboard + Project).
class DashboardTasklistTest < ActiveSupport::TestCase
  PREFIX = "https://tracker.example.com/organize/tasks/".freeze
  CYKL = { "id" => "101", "name" => "Cykl A", "url" => "https://tracker.example.com/organize/tasklists/101" }.freeze
  BACKLOG = { "id" => "102", "name" => "Backlog B", "url" => "https://tracker.example.com/organize/tasklists/102" }.freeze

  setup do
    @project = projects(:webapp)
    @project.update!(task_url_prefix: PREFIX, intum_api_token: "tajny")
    inbox_items(:requested).update!(task_url: "#{PREFIX}111")
    inbox_items(:commented).update!(task_url: "#{PREFIX}222")
    @third = InboxItem.create!(project: @project, pr_number: 9003, url: "https://github.com/acme/webapp/pull/9003",
                               reason: "requested", signal_at: 1.hour.ago)
    TrackerTask.create!(project: @project, number: "111", lists: [ CYKL, BACKLOG ], fetched_at: Time.current)
    TrackerTask.create!(project: @project, number: "222", lists: [ CYKL ], fetched_at: Time.current)
  end

  def dashboard = Dashboard.new(main_project: @project.reload)

  test "tasklist_options liczy PR-y per lista w kolejce projektu głównego" do
    assert_equal [ { "id" => "102", "name" => "Backlog B", "count" => 1 }, { "id" => "101", "name" => "Cykl A", "count" => 2 } ],
                 dashboard.tasklist_options
  end

  test "inny projekt główny — inne opcje" do
    assert_empty Dashboard.new(main_project: projects(:dashboard)).tasklist_options
  end

  test "bez wybranej listy wszystko jest na liście, nic pod kreską" do
    assert_equal dashboard.inbox_items, dashboard.inbox_items_on_list
    assert_empty dashboard.inbox_items_off_list
  end

  test "wybrana lista: jej PR-y widać, reszta (także bez zadania) ukryta" do
    @project.update!(inbox_tasklist_ids: [ "102" ])

    assert_equal [ 9001 ], dashboard.inbox_items_on_list.map(&:pr_number)
    assert_equal [ 9002, 9003 ].sort, dashboard.inbox_items_off_list.map(&:pr_number).sort
  end

  test "kilka wybranych list: PR z którejkolwiek z nich jest widoczny" do
    TrackerTask.create!(project: @project, number: "333", lists: [ { "id" => "104", "name" => "Incydenty", "url" => "x" } ])
    @third.update!(task_url: "#{PREFIX}333")
    @project.update!(inbox_tasklist_ids: [ "102", "104" ])

    assert_equal [ 9001, 9003 ].sort, dashboard.inbox_items_on_list.map(&:pr_number).sort
    assert_equal [ 9002 ], dashboard.inbox_items_off_list.map(&:pr_number)
  end

  test "zapisana lista spoza kolejki dalej jest w opcjach" do
    TrackerTask.create!(project: @project, number: "999", lists: [ { "id" => "103", "name" => "Stary cykl", "url" => "x" } ])
    @project.update!(inbox_tasklist_ids: [ "103" ])

    assert_includes dashboard.tasklist_options, { "id" => "103", "name" => "Stary cykl", "count" => 0 }
  end

  test "projekt bez trackera — brak opcji" do
    @project.update_columns(task_url_prefix: nil)

    assert_empty dashboard.tasklist_options
  end

  test "tracker wyłączony po wyborze listy — kolejka nie jest dzielona i nie ma chipów" do
    @project.update!(inbox_tasklist_ids: [ "102" ])
    @project.update_columns(task_url_prefix: nil)

    assert_empty dashboard.selected_tasklist_ids
    assert_empty dashboard.inbox_items_off_list
    assert_empty dashboard.tracker_lists_for(inbox_items(:requested).reload)
  end
end
