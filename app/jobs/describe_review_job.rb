class DescribeReviewJob < ApplicationJob
  queue_as :default

  def perform(review, github: GithubClient.new, worktrees: nil, session_factory: default_session_factory)
    worktrees ||= WorktreeManager.new(review.project)
    review.update!(status: "describing")

    if review.pr_url.present?
      info = github.pr_info(review.pr_url, repo_dir: review.project.repo_path)
      review.update!({ pr_number: info["number"], pr_title: info["title"], branch: info["headRefName"] }
                       .merge(task_link_attrs(review, info)))
      # Tytuł zadania od razu, nie dopiero po sesji opisu zadania - lista ma go
      # pokazać, zanim Claude skończy czytać zadanie. Osobnym jobem, żeby padnięty
      # tracker nie trzymał opisu PR-a. Także przy niepewnym linku: tytuł zadania
      # obok tytułu PR-a to najszybszy sposób, żeby człowiek ocenił, czy to to.
      CheckTaskCommentsJob.perform_later(review) if review.task_url.present?
      enqueue_task_description(review)
    end

    if review.branch.present?
      path = worktrees.ensure_for_branch(review.branch)
      review.update!(worktree_path: path)
      worktrees.checkout_pr(path, review.pr_url) if review.pr_url.present?
      # Dopiero po checkoucie: apka wstaje z kodu, który realnie leży w worktree.
      CheckWorktreeHealthJob.perform_later(review)
    else
      review.update!(worktree_path: review.project.repo_path)
    end

    run = review.claude_runs.create!(kind: "describe", claude_config: review.effective_claude_config)
    description = session_factory.call(run).call(PromptBuilder.describe(review))
    review.update!(description: description, status: "ready")
  rescue StandardError => e
    # Review mógł zostać usunięty z dashboardu w trakcie działania joba.
    return unless Review.exists?(review.id)

    review.fail!(e.message)
    # Opis zadania czekał na ten job (patrz enqueue_task_description) — bez tego
    # zostałby „w kolejce" na zawsze.
    review.update!(task_description_status: "failed") if review.task_description_status == "queued"
  end

  private

  # task_url z opisu PR-a, gdy nie przyszedł z formularza: konwencja zespołu mówi,
  # że zadanie jest w opisie podlinkowane, a bez tego linku cały poboczny cykl
  # (opis zadania, komentarz po decyzji) zostaje wyłączony. Link wpisany ręcznie
  # jest decyzją człowieka — nie podważamy go.
  def task_link_attrs(review, info)
    return {} if review.task_url.present?

    project = review.project
    check = TaskLinkCheck.new(prefix: project.task_url_prefix, intum: (project.intum_client if project.intum_enabled?))
                         .call(title: info["title"], body: info["body"])
    { task_url: check.url, task_link_status: check.status, task_link_note: check.note }
  end

  # Opis zadania startuje dopiero po ustaleniu linku (ReviewsController#create go
  # nie kolejkuje, gdy jest PR): inaczej sesja szukałaby zadania sama, zanim ten
  # job wybierze właściwe. Przy niepewnym linku czeka na potwierdzenie w panelu.
  def enqueue_task_description(review)
    return unless review.task_description_status == "queued"

    if review.task_link_uncertain?
      review.update!(task_description_status: "skipped")
    else
      DescribeTaskJob.perform_later(review)
    end
  end
end
