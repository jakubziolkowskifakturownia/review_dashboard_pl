require "test_helper"

class RefreshTrackerTasksJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PREFIX = "https://tracker.example.com/organize/tasks/".freeze
  CYKL = { "id" => "101", "name" => "Cykl A", "url" => "https://tracker.example.com/organize/tasklists/101" }.freeze
  BACKLOG = { "id" => "102", "name" => "Backlog B", "url" => "https://tracker.example.com/organize/tasklists/102" }.freeze

  class FakeTracker
    attr_reader :asked

    def initialize(lists = {}, failing: [], dropping: [], **by_number)
      @dropping = dropping
      @lists = lists.merge(by_number.transform_keys(&:to_s))
      @failing = failing
      @asked = Queue.new
    end

    def task_lists(number)
      @asked << number
      raise IntumClient::Error, "tracker odpowiedział 500" if @failing.include?(number)
      raise EOFError, "end of file reached" if @dropping&.include?(number)

      @lists.fetch(number, [])
    end

    def asked_numbers = Array.new(@asked.size) { @asked.pop }.sort
  end

  setup do
    @project = projects(:webapp)
    @project.update!(task_url_prefix: PREFIX, intum_api_token: "tajny")
    InboxItem.create!(project: @project, pr_number: 1, url: "https://github.com/acme/webapp/pull/1",
                      reason: "requested", task_url: "#{PREFIX}111")
    InboxItem.create!(project: @project, pr_number: 2, url: "https://github.com/acme/webapp/pull/2",
                      reason: "requested", task_url: nil)
    Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/3", task_url: "#{PREFIX}t/222")
  end

  test "pobiera listy dla zadań z kolejki i z review projektu" do
    tracker = FakeTracker.new("111" => [ CYKL ], "222" => [ CYKL, BACKLOG ])

    RefreshTrackerTasksJob.perform_now(@project, client: tracker)

    assert_equal %w[111 222], tracker.asked_numbers
    assert_equal({ "111" => [ CYKL ], "222" => [ CYKL, BACKLOG ] }, TrackerTask.lists_by_number(@project))
  end

  test "bez force pomija świeże, pobiera starsze niż 6h" do
    TrackerTask.create!(project: @project, number: "111", lists: [ CYKL ], fetched_at: 1.hour.ago)
    TrackerTask.create!(project: @project, number: "222", lists: [ CYKL ], fetched_at: 7.hours.ago)
    tracker = FakeTracker.new("222" => [ BACKLOG ])

    RefreshTrackerTasksJob.perform_now(@project, client: tracker)

    assert_equal %w[222], tracker.asked_numbers
  end

  test "force nadpisuje listy zadania przepiętego na inną listę" do
    TrackerTask.create!(project: @project, number: "111", lists: [ CYKL ], fetched_at: 1.minute.ago)
    tracker = FakeTracker.new("111" => [ BACKLOG ])

    RefreshTrackerTasksJob.perform_now(@project, force: true, client: tracker)

    assert_equal [ BACKLOG ], TrackerTask.lists_by_number(@project)["111"]
  end

  test "błąd trackera dla jednego zadania nie blokuje pozostałych" do
    TrackerTask.create!(project: @project, number: "111", lists: [ CYKL ], fetched_at: 1.day.ago)
    tracker = FakeTracker.new({ "222" => [ BACKLOG ] }, failing: %w[111])

    RefreshTrackerTasksJob.perform_now(@project, client: tracker)

    lists = TrackerTask.lists_by_number(@project)
    assert_equal [ CYKL ], lists["111"]
    assert_equal [ BACKLOG ], lists["222"]
  end

  test "projekt bez trackera — nic nie robi" do
    @project.update_columns(task_url_prefix: nil)
    tracker = FakeTracker.new

    RefreshTrackerTasksJob.perform_now(@project, client: tracker)

    assert_empty tracker.asked_numbers
    assert_equal 0, TrackerTask.count
  end

  test "po zapisie odświeża dashboard" do
    assert_enqueued_with(job: BroadcastDashboardJob) do
      RefreshTrackerTasksJob.perform_now(@project, client: FakeTracker.new("111" => [ CYKL ]))
    end
  end

  test "harmonogram dzienny odświeża z force projekty z trackerem" do
    clear_enqueued_jobs # review z setupu zlecił już swoje odświeżenie
    assert_enqueued_with(job: RefreshTrackerTasksJob, args: [ @project, { force: true } ]) do
      RefreshAllTrackerTasksJob.perform_now
    end
    assert_equal 1, enqueued_jobs.count { |job| job["job_class"] == "RefreshTrackerTasksJob" }
  end

  test "odświeżenie kolejki GitHuba dokłada pobranie list" do
    inbox = Object.new
    def inbox.refresh(_project) = nil

    assert_enqueued_with(job: RefreshTrackerTasksJob, args: [ @project ]) do
      RefreshInboxJob.perform_now(@project, inbox: inbox)
    end
  end

  test "nowy link do zadania w review zleca pobranie list" do
    review = Review.create!(project: @project, pr_url: "https://github.com/acme/webapp/pull/4")

    assert_enqueued_with(job: RefreshTrackerTasksJob, args: [ @project ]) do
      review.update!(task_url: "#{PREFIX}333")
    end
  end

  test "zerwane połączenie przy jednym zadaniu nie gubi pozostałych" do
    tracker = FakeTracker.new({ "222" => [ BACKLOG ] }, dropping: %w[111])

    RefreshTrackerTasksJob.perform_now(@project, client: tracker)

    assert_equal({ "222" => [ BACKLOG ] }, TrackerTask.lists_by_number(@project))
  end
end
