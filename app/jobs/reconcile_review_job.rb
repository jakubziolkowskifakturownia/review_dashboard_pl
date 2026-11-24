# Uzgodnienie wyniku review z werdyktami weryfikatora i zgodnością z zadaniem: wznawia
# sesję review i pozwala jej rozstrzygnąć znaleziska obalone/sporne oraz poprawić (z dowodem)
# oceny zgodności. Cykl poboczny jak CompactReviewJob: pożycza status „reviewing" na czas
# sesji (blokuje inne akcje na review) i oddaje poprzedni.
class ReconcileReviewJob < ApplicationJob
  queue_as :default

  def perform(review, previous_status, session_factory: default_session_factory)
    config = review.effective_claude_config
    # Bez sesji na tym koncie (np. po przełączeniu) sesja startuje świeża i dostaje
    # kontekst z promptu.
    base = review.resumable_session_run(config)

    run = review.claude_runs.create!(kind: "reconcile", claude_config: config,
                                     resume_session_id: base&.session_id,
                                     previous_status: previous_status)
    session_factory.call(run).call(PromptBuilder.reconcile(review, resumed: base.present?))
    ReconcileResultImporter.call(review, written_after: run.created_at)
  rescue StandardError => e
    # Świadomie bez fail!, mark_reviewed! i task_fit: nieudane uzgodnienie niczego nie psuje —
    # review dalej ma swój wynik. „failed" podstawiłoby pod „Ponów" ostatni run kindu
    # `reconcile`, którego te ścieżki nie umieją wznowić. Powód widać na runie.
    Rails.logger.warn("Reconcile review #{review.id}: #{e.message}")
  ensure
    # Review mógł zostać usunięty z dashboardu w trakcie działania joba. Zmiana statusu
    # odświeża panel przez callback after_update_commit.
    review.update!(status: previous_status) if Review.exists?(review.id)
  end
end
