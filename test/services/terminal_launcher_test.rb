require "test_helper"

class TerminalLauncherTest < ActiveSupport::TestCase
  class FakeRunner
    attr_reader :calls

    def initialize(result)
      @result = result
      @calls = []
    end

    def run(cmd, env: {}, chdir:, timeout: 600, stdin_data: nil)
      @calls << cmd
      @result
    end
  end

  def result(exit_code:, stderr: "")
    CommandRunner::Result.new(exit_code: exit_code, stdout: "", stderr: stderr, timed_out: false)
  end

  # Komenda wklejona w treść AppleScriptu zamieniłaby cudzysłów ze ścieżki w kod
  # skryptu. Jako argument osascript zostaje zwykłym napisem.
  test "komenda jedzie do osascript jako argument, a nie w treści skryptu" do
    runner = FakeRunner.new(result(exit_code: 0))
    TerminalLauncher.open(%(cd "/wt" && claude --resume abc), runner: runner)

    cmd = runner.calls.sole
    assert_equal "osascript", cmd.first
    assert_equal %(cd "/wt" && claude --resume abc), cmd.last
    assert_not_includes cmd[0..-2].join, "claude --resume"
  end

  test "porażka osascript zgłasza błąd z jego komunikatem" do
    runner = FakeRunner.new(result(exit_code: 1, stderr: "Not authorized to send Apple events to iTerm."))
    error = assert_raises(TerminalLauncher::Failed) { TerminalLauncher.open("ls", runner: runner) }
    assert_match(/Not authorized/, error.message)
  end
end
