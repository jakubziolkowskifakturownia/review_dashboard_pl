# Lewa kolumna dashboardu w zakładce self review: własny kod do przejrzenia, zanim zobaczy
# go ktoś inny — otwarte PR-y autora i lokalne branche bez PR-a. Liczone na żywo, nie
# w inbox_items: GithubInbox#refresh kasuje wszystko, czego nie zebrał, więc padnięty
# `gh` czyściłby tę listę razem z kolejką „czeka na Twoje review".
class SelfReviewBoard
  Section = Data.define(:project, :prs, :prs_error, :branches)

  RECENT_LIMIT = 30

  def initialize(projects: Project.active.by_name, github: GithubClient.new)
    @projects = projects.to_a
    @github = github
  end

  def sections
    @sections ||= @projects.map { |project| section_for(project) }
  end

  # Klasowa, bo broadcast z tła przerysowuje tę sekcję bez reszty zakładki — bez `gh`
  # i gita, które liczą się tylko przy wejściu na stronę.
  def self.recent_reviews
    Review.self_reviews.includes(:project, :findings).order(id: :desc).limit(RECENT_LIMIT).to_a
  end

  def recent_reviews = @recent_reviews ||= self.class.recent_reviews

  # Wiersze kolejki przez wszystkie projekty, najświeższe na górze — jak „Czeka na Twoje
  # review", gdzie kolejność mówi, co ruszało się ostatnio.
  def pr_rows
    sections.flat_map { |section| section.prs.map { |pr| [ section.project, pr ] } }
            .sort_by { |_, pr| pr["updatedAt"].to_s }.reverse
  end

  def branch_rows
    sections.flat_map { |section| section.branches.map { |branch| [ section.project, branch ] } }
            .sort_by { |_, branch| branch.committed_at || Time.at(0) }.reverse
  end

  def pr_errors = sections.select(&:prs_error).map { |section| [ section.project, section.prs_error ] }

  # Wiersz z istniejącym review linkuje do niego zamiast zamawiać drugie — klucz jak
  # w pr_url_not_duplicated, żeby /files i inna wielkość liter nie mnożyły review.
  def review_for_pr(url) = reviews_by_pr[GithubClient.pr_key(url)]

  def review_for_branch(project, branch) = reviews_by_branch[[ project.id, branch ]]

  private

  def section_for(project)
    prs, error = my_prs(project)
    branches = LocalBranches.new(project).list(except: prs.map { |pr| pr["headRefName"] })
    Section.new(project:, prs:, prs_error: error, branches:)
  end

  # Błąd `gh` zostaje przy projekcie, zamiast kłaść stronę: lokalne branche nie
  # potrzebują GitHuba i mają się pokazać mimo braku logowania czy sieci.
  def my_prs(project)
    return [ [], "brak adresu repo na GitHubie w ustawieniach projektu" ] if project.github_slug.blank?

    [ @github.my_open_prs(repo: project.github_slug, repo_dir: project.repo_path), nil ]
  rescue GithubClient::Error, SystemCallError, JSON::ParserError => e
    [ [], e.message ]
  end

  # select: wiersz potrzebuje tylko linku i statusu, a pełne rekordy niosą opisy i JSON-y.
  def reviews_by_pr
    @reviews_by_pr ||= Review.where(project: @projects).where.not(pr_url: [ nil, "" ])
                             .select(:id, :pr_url, :status).index_by { |review| GithubClient.pr_key(review.pr_url) }
  end

  def reviews_by_branch
    @reviews_by_branch ||= Review.self_reviews.where(project: @projects).where.not(branch: [ nil, "" ])
                                 .select(:id, :project_id, :branch, :status)
                                 .index_by { |review| [ review.project_id, review.branch ] }
  end
end
