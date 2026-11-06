require "test_helper"

class TaskLinksControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @review = reviews(:pr_review)
    @review.update!(task_url: "https://tasks.example.com/444", task_link_status: "uncertain",
                    task_link_note: "tytuł mówi #555", task_description_status: "skipped")
  end

  test "potwierdzenie tego samego linku zdejmuje blokadę i kolejkuje opis zadania" do
    assert_enqueued_with(job: DescribeTaskJob, args: [ @review ]) do
      patch review_task_link_path(@review)
    end
    @review.reload
    assert_equal [ "https://tasks.example.com/444", "confirmed", nil, "queued" ],
                 [ @review.task_url, @review.task_link_status, @review.task_link_note, @review.task_description_status ]
    assert_not @review.task_link_uncertain?
    assert_redirected_to review_path(@review)
  end

  test "nowy link czyści wszystko, co dotyczyło starego zadania" do
    @review.update!(task_title: "Stare", task_description: "opis starego", task_description_status: "ready",
                    task_criteria: { "criteria" => [ { "id" => "ac1", "text" => "x" } ] }, task_comments_seen: 3)

    patch review_task_link_path(@review), params: { task_url: "https://tasks.example.com/555" }

    @review.reload
    assert_equal "https://tasks.example.com/555", @review.task_url
    assert_nil @review.task_title
    assert_nil @review.task_description
    assert_nil @review.task_criteria
    assert_nil @review.task_comments_seen
    assert_equal "queued", @review.task_description_status
  end

  test "gotowy opis tego samego zadania: bez nowej sesji opisu, a zakończone review dostaje bramkę" do
    @review.update!(status: "reviewed", branch: "sl-fix", task_description_status: "ready",
                    task_criteria: { "criteria" => [ { "id" => "ac1", "text" => "x" } ] })

    assert_no_enqueued_jobs(only: DescribeTaskJob) do
      assert_enqueued_with(job: TaskFitJob) { patch review_task_link_path(@review) }
    end
  end

  test "zmiana linku w trakcie generowania opisu jest odrzucana" do
    @review.update!(task_description_status: "running")
    patch review_task_link_path(@review), params: { task_url: "https://tasks.example.com/555" }
    assert_equal "uncertain", @review.reload.task_link_status
  end
end
