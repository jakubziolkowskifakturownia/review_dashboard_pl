require "test_helper"

class ReconcileReviewJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @config = Dir.mktmpdir
    @workdir = Dir.mktmpdir
    @review = reviews(:pr_review)
    @review.update!(status: "reviewing", worktree_path: @workdir, summary: "Stare podsumowanie")
    # update_column: @config to tmpdir testowy, nie jeden z prawdziwych configów z listy.
    @review.update_column(:claude_config, @config)
    @base_run = succeeded_run("review", "sess-base")
    @finding = @review.findings.create!(priority: "important", title: "F", body: "x", verdict: "refuted", verdict_note: "nie")
    FileUtils.rm_rf(@review.artifacts_dir)
    FileUtils.mkdir_p(@review.artifacts_dir)
  end

  teardown do
    FileUtils.remove_entry(@config)
    FileUtils.remove_entry(@workdir)
    FileUtils.rm_rf(@review.artifacts_dir)
  end

  def succeeded_run(kind, session_id, config: @config)
    run = @review.claude_runs.create!(kind: kind, claude_config: config, status: "succeeded", session_id: session_id)
    path = run.session_file(config)
    FileUtils.mkdir_p(path.dirname)
    File.write(path, "{}")
    run
  end

  def session_writing_reconcile(payload)
    path = @review.artifacts_dir.join("reconcile.json")
    lambda do |_run|
      Object.new.tap do |s|
        s.define_singleton_method(:call) do |_prompt|
          File.write(path, payload.to_json)
          "done"
        end
      end
    end
  end

  test "wznawia sesję, importuje reconcile.json i wraca do poprzedniego statusu bez task_fit" do
    payload = { summary: "Nowe podsumowanie",
                findings: [ { id: @finding.id, resolution: "dropped", note: "racja" } ] }
    ReconcileReviewJob.perform_now(@review, "decided", session_factory: session_writing_reconcile(payload))
    run = @review.claude_runs.where(kind: "reconcile").sole
    @review.reload
    assert_equal({ status: "decided", summary: "Nowe podsumowanie", kind: "reconcile",
                   resume: "sess-base", previous: "decided", resolution: "dropped" },
                 { status: @review.status, summary: @review.summary, kind: run.kind,
                   resume: run.resume_session_id, previous: run.previous_status,
                   resolution: @finding.reload.resolution })
    assert_no_enqueued_jobs(only: TaskFitJob)
  end

  test "porażka sesji nie oznacza review jako failed" do
    factory = ->(_run) { Object.new.tap { |s| s.define_singleton_method(:call) { |_p| "gadanie bez pliku" } } }
    ReconcileReviewJob.perform_now(@review, "reviewed", session_factory: factory)
    @review.reload
    assert_equal [ "reviewed", nil ], [ @review.status, @review.error_message ]
  end

  test "usunięty review nie wywraca joba" do
    review = @review
    factory = lambda do |_run|
      Object.new.tap { |s| s.define_singleton_method(:call) { |_p| review.destroy } }
    end
    assert_nothing_raised do
      ReconcileReviewJob.perform_now(@review, "reviewed", session_factory: factory)
    end
  end
end
