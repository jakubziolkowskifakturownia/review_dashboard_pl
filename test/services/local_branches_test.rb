require "test_helper"

class LocalBranchesTest < ActiveSupport::TestCase
  # Odpowiedź po komendzie, nie po kolejności: liczba wywołań rev-list zależy od
  # listy branchy, a test ma mówić o wyniku, nie o kolejności spawnów.
  class FakeRunner
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    def run(cmd, env: {}, chdir:, timeout: 600, stdin_data: nil)
      @calls << { cmd: cmd, chdir: chdir }
      stdout = @responses.fetch(cmd) { return CommandRunner::Result.new(exit_code: 1, stdout: "", stderr: "unknown", timed_out: false) }
      CommandRunner::Result.new(exit_code: 0, stdout: stdout, stderr: "", timed_out: false)
    end
  end

  REFS = [ "git", "for-each-ref", "--sort=-committerdate",
           "--format=%(refname:short)%09%(committerdate:iso-strict)", "refs/heads" ].freeze
  WORKTREES = [ "git", "worktree", "list", "--porcelain" ].freeze
  BASE = [ "git", "rev-parse", "--verify", "--quiet", "origin/master" ].freeze

  def ahead(branch) = [ "git", "rev-list", "--count", "origin/master..#{branch}" ]

  setup do
    @project = projects(:webapp)
    @responses = {
      REFS => "jz_fresh\t2026-10-21T10:00:00+02:00\nmaster\t2026-10-20T09:00:00+02:00\n" \
              "jz_with_pr\t2026-10-19T09:00:00+02:00\njz_merged\t2026-10-18T09:00:00+02:00\n",
      WORKTREES => "worktree #{@project.repo_path}\nbranch refs/heads/master\n\n" \
                   "worktree /wt/webapp-jz_fresh\nbranch refs/heads/jz_fresh\n",
      BASE => "abc123\n",
      ahead("jz_fresh") => "3\n",
      ahead("jz_with_pr") => "1\n",
      ahead("jz_merged") => "0\n"
    }
  end

  test "should list branches with unpushed work, newest first, with their worktree" do
    branches = LocalBranches.new(@project, runner: FakeRunner.new(@responses)).list(except: %w[jz_with_pr])

    assert_equal [ "jz_fresh" ], branches.map(&:name)
    fresh = branches.sole
    assert_equal 3, fresh.ahead
    assert_equal "/wt/webapp-jz_fresh", fresh.worktree_path
    assert_equal Time.zone.parse("2026-10-21T10:00:00+02:00"), fresh.committed_at
  end

  test "should not spawn rev-list for the base branch nor for excluded branches" do
    runner = FakeRunner.new(@responses)
    LocalBranches.new(@project, runner: runner).list(except: %w[jz_with_pr])

    counted = runner.calls.map { |c| c[:cmd] }.select { |cmd| cmd[1] == "rev-list" }
    assert_equal [ ahead("jz_fresh"), ahead("jz_merged") ], counted
    assert runner.calls.all? { |c| c[:chdir] == @project.repo_path }
  end

  test "should fall back to origin/main when the repo has no origin/master" do
    @responses.delete(BASE)
    @responses[[ "git", "rev-parse", "--verify", "--quiet", "origin/main" ]] = "abc\n"
    @responses[[ "git", "rev-list", "--count", "origin/main..jz_fresh" ]] = "2\n"

    branches = LocalBranches.new(@project, runner: FakeRunner.new(@responses)).list

    assert_equal [ [ "jz_fresh", 2 ] ], branches.map { |b| [ b.name, b.ahead ] }
  end

  test "should skip branches whose names the review form would reject" do
    @responses[REFS] = "jz+bad\t2026-10-21T10:00:00+02:00\n" + @responses[REFS]
    @responses[ahead("jz+bad")] = "4\n"

    branches = LocalBranches.new(@project, runner: FakeRunner.new(@responses)).list(except: %w[jz_with_pr])

    assert_equal [ "jz_fresh" ], branches.map(&:name)
  end

  test "should degrade to an empty list when git fails" do
    assert_equal [], LocalBranches.new(@project, runner: FakeRunner.new({})).list
  end
end
