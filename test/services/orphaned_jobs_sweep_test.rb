require "test_helper"

class OrphanedJobsSweepTest < ActiveSupport::TestCase
  # Baza kolejki nie istnieje w środowisku testowym — relację osieroconych claimów
  # podmieniamy na atrapę, która notuje release_all.
  class FakeClaims
    attr_reader :released

    def initialize = @released = false

    def release_all = @released = true
  end

  setup do
    @review = reviews(:pr_review)
    @claims = FakeClaims.new
  end

  test "dobija sesje martwego workera i oddaje jego joby do kolejki" do
    dead = @review.claude_runs.create!(kind: "describe", claude_config: "/x", status: "running",
                                       pid: 12_345, supervisor_pid: 999_999_999)
    alive = @review.claude_runs.create!(kind: "describe_task", claude_config: "/x", status: "running",
                                        pid: 54_321, supervisor_pid: Process.pid)
    killed = []
    OrphanedRunsCleanup.stub :process_alive?, ->(pid) { pid == Process.pid || pid == 12_345 } do
      CommandRunner.stub :kill_group, ->(pid, **) { killed << pid } do
        OrphanedJobsSweep.call(orphaned_claims: @claims)
      end
    end
    assert_equal(
      { killed: [ 12_345 ], dead: "aborted", alive: "running", released: true },
      { killed: killed, dead: dead.reload.status, alive: alive.reload.status, released: @claims.released }
    )
  end

  # Review w trakcie (np. tworzenie worktree bez sesji) nie może dostać „Ponów" —
  # jego job zaraz wróci do kolejki i dokończy pracę.
  test "nie oblewa review, którego job wraca do kolejki" do
    @review.update!(status: "describing")
    OrphanedJobsSweep.call(orphaned_claims: @claims)
    assert_equal "describing", @review.reload.status
  end

  # Job takiej sesji Solid Queue oblewa razem z martwym workerem i nikt go nie ponowi —
  # bez tego panel w nieskończoność pokazuje „sprawdzam" bez przycisku ponowienia.
  test "przerwana sesja cyklu pobocznego zdejmuje jego status running" do
    @review.update!(task_fit_status: "running", task_description_status: "ready")
    @review.claude_runs.create!(kind: "task_fit", claude_config: "/x", status: "running", supervisor_pid: 999_999_999)
    CommandRunner.stub :kill_group, ->(*_args, **) { } do
      OrphanedJobsSweep.call(orphaned_claims: @claims)
    end
    @review.reload
    assert_equal({ task_fit: "failed", task_description: "ready" },
                 { task_fit: @review.task_fit_status, task_description: @review.task_description_status })
  end
end
