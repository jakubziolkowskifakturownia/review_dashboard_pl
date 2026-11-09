# Review z opisem zadania zebranym wcześniej (np. audyt w Claude Code): bez sesji DescribeTaskJob,
# reszta (opis zmian, worktree, Start) jak z formularza. Istniejące review PR-a dostaje nowy opis.
namespace :reviews do
  desc "Review z gotowym opisem zadania: PR=<url> TASK=<plik.json> [BRANCH=<branch>]"
  task prefill: :environment do
    url = ENV.fetch("PR")
    task = JSON.parse(File.read(ENV.fetch("TASK")))
    project = Project.active.find { |p| p.github_slug && url.include?("github.com/#{p.github_slug}/") }
    abort "Brak aktywnego projektu dla #{url}" unless project

    attrs = { task_url: task["url"], task_title: task["title"], task_description: task["description"],
              task_description_status: "ready" }
    attrs[:task_criteria] = task["criteria"].slice(*Review::TASK_FIT_SECTIONS.keys) if task["criteria"]

    review = project.reviews.new(pr_url: url, branch: ENV["BRANCH"], **attrs)
    review.claude_config = review.effective_claude_config
    if review.save
      DescribeReviewJob.perform_later(review)
    elsif (review = review.duplicate_review)
      review.update!(attrs)
    else
      abort project.reviews.new(pr_url: url, **attrs).tap(&:validate).errors.full_messages.to_sentence
    end

    tracker = review.tracker_task_attrs
    if (count = tracker[:task_comments_latest])
      tracker.merge!(task_comments_seen: count, task_comments_checked_at: Time.current)
    end
    review.update!(tracker) if tracker.any?
    puts "review #{review.id}: http://localhost:3020/reviews/#{review.id}"
  end
end
