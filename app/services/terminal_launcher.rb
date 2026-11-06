# Otwiera komendę w nowej karcie iTerm na tym Macu — po to, żeby po review w tle
# porozmawiać z tą samą sesją Claude bez kopiowania komendy. `write text` zamiast
# `command`: karta zostaje po wyjściu z claude, z shellem w katalogu sesji.
# Komenda jedzie do osascript jako argument (argv), a nie wklejona w treść
# skryptu: cudzysłów w ścieżce nie zamieni się wtedy w kod AppleScriptu.
class TerminalLauncher
  Failed = Class.new(StandardError)

  SCRIPT = <<~APPLESCRIPT
    on run argv
      tell application "iTerm"
        activate
        if (count of windows) is 0 then
          create window with default profile
        else
          tell current window to create tab with default profile
        end if
        tell current session of current window to write text (item 1 of argv)
      end tell
    end run
  APPLESCRIPT

  def self.open(command, runner: CommandRunner)
    result = runner.run([ "osascript", "-e", SCRIPT, command ], chdir: Dir.home, timeout: 30)
    raise Failed, result.stderr.presence || "osascript zakończył się kodem #{result.exit_code}" unless result.success?
  end
end
