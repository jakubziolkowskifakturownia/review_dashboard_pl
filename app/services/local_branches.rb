# Lokalne branche repo projektu z commitami ponad gałąź główną — kandydaci do selfreview,
# zanim powstanie z nich PR. Czyta tylko gita: nic nie fetchuje i nic nie tworzy, więc
# stan origin/master jest taki, jak przy ostatnim fetchu w repo.
class LocalBranches
  Branch = Data.define(:name, :ahead, :committed_at, :worktree_path)

  # Każdy kandydat to osobny spawn `git rev-list` — limit trzyma zakładkę w ułamku sekundy
  # także w repo z setkami starych branchy.
  CANDIDATES_LIMIT = 30
  BASE_CANDIDATES = %w[origin/master origin/main].freeze
  BASE_NAMES = %w[master main].freeze
  # Lokalny git odpowiada w milisekundach; dłużej znaczy zawieszony dysk albo lock,
  # a strona czeka na wynik w requeście.
  GIT_TIMEOUT = 10

  def initialize(project, runner: CommandRunner)
    @project = project
    @runner = runner
  end

  # `except`: branche, które mają już otwarty PR — trafiają do sekcji PR-ów, nie tu.
  # Miękka degradacja do []: zakładka ma się otworzyć także przy zepsutym repo.
  def list(except: [])
    base = base_ref or return []
    worktrees = worktree_paths

    # BRANCH_FORMAT: branch, którego review nie przyjmie walidacją, nie dostaje
    # przycisku „Zleć review”, który skończyłby się błędem formularza.
    refs.select { |name, _| name.match?(Review::BRANCH_FORMAT) }
        .reject { |name, _| BASE_NAMES.include?(name) || except.include?(name) }
        .first(CANDIDATES_LIMIT)
        .filter_map do |name, committed_at|
          ahead = ahead_of(base, name)
          Branch.new(name:, ahead:, committed_at:, worktree_path: worktrees[name]) if ahead.positive?
        end
  rescue SystemCallError
    # Nieistniejący repo_path wywala już samo spawnowanie procesu (ENOENT z chdir).
    []
  end

  private

  def base_ref
    BASE_CANDIDATES.find { |ref| git("rev-parse", "--verify", "--quiet", ref) }
  end

  def refs
    output = git("for-each-ref", "--sort=-committerdate",
                 "--format=%(refname:short)%09%(committerdate:iso-strict)", "refs/heads").to_s
    output.lines.filter_map do |line|
      name, date = line.chomp.split("\t", 2)
      [ name, Time.zone.parse(date.to_s) ] if name.present?
    end
  end

  def worktree_paths
    git("worktree", "list", "--porcelain").to_s.split("\n\n").each_with_object({}) do |entry, paths|
      lines = entry.lines.map(&:chomp)
      branch = lines.find { |line| line.start_with?("branch refs/heads/") }&.delete_prefix("branch refs/heads/")
      paths[branch] = lines.first.delete_prefix("worktree ") if branch
    end
  end

  def ahead_of(base, name)
    git("rev-list", "--count", "#{base}..#{name}").to_i
  end

  # stdout albo nil — pojedynczy padnięty git (usunięty branch w trakcie, brak refa)
  # pomija jeden wiersz zamiast wywracać całą listę.
  def git(*args)
    result = @runner.run([ "git", *args ], chdir: @project.repo_path, timeout: GIT_TIMEOUT)
    result.stdout if result.success?
  end
end
