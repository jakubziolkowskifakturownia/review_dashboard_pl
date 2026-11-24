# Czyta reconcile.json zapisany przez wznowioną sesję review i nakłada go na istniejące
# rekordy: rozstrzyga znaleziska obalone/sporne oraz (z dowodem) poprawia oceny zgodności
# z zadaniem. Niczego nie kasuje poza znaleziskami bramki zgodności, które przelicza od nowa.
# Werdykty weryfikatora, `raw_result` i oryginalny wynik `task_fit` zostają nietknięte -
# zmiany zgodności lądują w nakładce `reviews.task_fit_reconciliation`. Każde uzgodnienie
# zastępuje nakładkę w całości: zmiany porównujemy z oryginałem, nie scalamy z poprzednią.
class ReconcileResultImporter
  Missing = Class.new(StandardError)
  FILENAME = "reconcile.json"
  RECONCILABLE_VERDICTS = %w[refuted disputed].freeze

  # `written_after`: start sesji - jak w ReviewResultImporter, reconcile.json poprzedniego
  # przebiegu zostaje na dysku i sama obecność pliku nie dowodzi, że ta sesja go zapisała.
  def self.call(review, written_after: nil)
    path = review.artifacts_dir.join(FILENAME)
    raise Missing, "Sesja nie zapisała #{path} - uzgodnienie niedokończone" unless File.exist?(path)
    if written_after && File.mtime(path) < written_after.floor
      raise Missing, "Sesja nie zapisała nowego #{path} - na dysku jest wynik poprzedniego przebiegu"
    end

    import(review, JSON.parse(File.read(path)))
  end

  def self.import(review, data)
    new(review, data).import
  end

  def initialize(review, data)
    @review = review
    @data = data
  end

  def import
    @review.transaction do
      resolve_findings
      reconcile_task_fit
      @review.update!(summary: @data["summary"]) if @data["summary"].present?
    end
  end

  private

  def resolve_findings
    candidates = @review.findings.from_review.where(verdict: RECONCILABLE_VERDICTS).index_by(&:id)
    Array(@data["findings"]).each do |entry|
      finding = candidates[entry["id"]]
      next unless finding && Finding::RESOLUTIONS.include?(entry["resolution"])

      attrs = { resolution: entry["resolution"], resolution_note: entry["note"] }
      attrs[:priority] = entry["priority"] if entry["resolution"] == "downgraded" && lower_priority?(entry["priority"], finding.priority)
      finding.update!(attrs)
    end
  end

  # PRIORITIES jest posortowane od najwyższego, więc niższy priorytet = większy indeks.
  def lower_priority?(candidate, current)
    Finding::PRIORITIES.index(candidate)&.> Finding::PRIORITIES.index(current)
  end

  def reconcile_task_fit
    return unless @review.task_fit_status == "ready" && @review.task_fit.present?

    items = @review.task_fit_original_items
    changes = accepted_changes(items)
    evidence = accepted_evidence
    items = items.map { |item| (change = changes[item["id"].to_s]) ? item.merge("status" => change["to"], "note" => change["note"]) : item }
    evidence_found = evidence ? evidence["to"] : @review.task_fit["evidence_found"]
    overlay = if changes.empty? && evidence.nil?
      nil
    else
      { "changes" => changes, "evidence_found" => evidence,
        "verdict" => TaskFitImporter.verdict_for(items, evidence_found), "at" => Time.current.iso8601 }
    end
    @review.update!(task_fit_reconciliation: overlay)
    # Zawsze od nowa: poprzednie uzgodnienie mogło zostawić znaleziska z innego zestawu punktów.
    rebuild_task_fit_findings(items, evidence_found)
  end

  # Zmiana punktu: id znane, status dozwolony dla rodzaju i różny od oryginału, note niepusta.
  def accepted_changes(items)
    by_id = items.index_by { |item| item["id"].to_s }
    Array(@data["task_fit_changes"]).each_with_object({}) do |entry, accepted|
      item = by_id[entry["id"].to_s] or next
      allowed, = TaskFitImporter::RULES[item["kind"]]
      next unless allowed&.include?(entry["status"]) && entry["status"] != item["status"] && entry["note"].present?

      accepted[item["id"].to_s] = { "from" => item["status"], "to" => entry["status"], "note" => entry["note"] }
    end
  end

  def accepted_evidence
    entry = @data["evidence_found"]
    return unless entry.is_a?(Hash) && [ true, false ].include?(entry["value"]) && entry["note"].present?

    original = @review.task_fit["evidence_found"] == true
    { "from" => original, "to" => entry["value"], "note" => entry["note"] } unless entry["value"] == original
  end

  def rebuild_task_fit_findings(items, evidence_found)
    result = @review.task_fit.slice("symptom", "assumed_cause", "evidence").merge("evidence_found" => evidence_found)
    @review.findings.from_task_fit.destroy_all
    TaskFitImporter.findings_attributes(items, result).each { |attrs| @review.findings.create!(attrs.merge(source: "task_fit")) }
  end
end
