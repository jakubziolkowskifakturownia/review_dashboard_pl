require "test_helper"

class ReconcileResultImporterTest < ActiveSupport::TestCase
  setup do
    @review = reviews(:pr_review)
    @review.update!(
      summary: "stare", raw_result: '{"raw":true}',
      task_criteria: { "criteria" => [ { "id" => "ac1", "text" => "Kod 2FA dochodzi do klienta" },
                                       { "id" => "ac2", "text" => "count: 0 to porażka" } ],
                       "traps" => [], "process" => [] }
    )
    @refuted = @review.findings.create!(priority: "important", title: "F1", body: "x", verdict: "refuted", verdict_note: "nie")
    @confirmed = @review.findings.create!(priority: "important", title: "F2", body: "x", verdict: "confirmed")
    @important = @review.findings.create!(priority: "important", title: "F", body: "x", verdict: "disputed")
    @minor = @review.findings.create!(priority: "minor", title: "G", body: "x", verdict: "disputed")
    TaskFitImporter.import(@review, "symptom" => "s", "assumed_cause" => "c", "evidence" => "e", "evidence_found" => true,
                                    "criteria" => [ { "id" => "ac1", "status" => "unmet", "note" => "brak" },
                                                    { "id" => "ac2", "status" => "met", "note" => "ok" } ])
    @review.reload
    FileUtils.rm_rf(@review.artifacts_dir)
    FileUtils.mkdir_p(@review.artifacts_dir)
  end

  teardown { FileUtils.rm_rf(@review.artifacts_dir) }

  def import(data)
    ReconcileResultImporter.import(@review, data)
    @review.reload
  end

  test "rozstrzygnięcia trafiają tylko do obalonych i spornych, werdykty zostają" do
    count = @review.findings.count
    import("findings" => [ { "id" => @refuted.id, "resolution" => "dropped", "note" => "weryfikator ma rację" },
                           { "id" => @confirmed.id, "resolution" => "dropped", "note" => "x" } ])
    @refuted.reload
    assert_equal [ "dropped", "weryfikator ma rację", "refuted", "nie" ],
                 [ @refuted.resolution, @refuted.resolution_note, @refuted.verdict, @refuted.verdict_note ]
    assert_nil @confirmed.reload.resolution
    assert_equal count, @review.findings.count
  end

  test "downgraded obniża priorytet, ale nigdy go nie podnosi" do
    import("findings" => [ { "id" => @important.id, "resolution" => "downgraded", "priority" => "minor", "note" => "a" },
                           { "id" => @minor.id, "resolution" => "downgraded", "priority" => "critical", "note" => "b" } ])
    assert_equal [ "minor", "downgraded" ], [ @important.reload.priority, @important.resolution ]
    assert_equal [ "minor", "downgraded", "b" ], [ @minor.reload.priority, @minor.resolution, @minor.resolution_note ]
  end

  test "nieznane id i resolution spoza słownika są pomijane" do
    import("findings" => [ { "id" => 0, "resolution" => "dropped", "note" => "x" },
                           { "id" => @refuted.id, "resolution" => "whatever", "note" => "x" } ])
    assert_nil @refuted.reload.resolution
    assert_nil @review.task_fit_reconciliation
  end

  test "zmiana punktu z dowodem przelicza werdykt i znaleziska zgodności, oryginał nietknięty" do
    assert_equal "misses", @review.task_fit_verdict
    assert @review.findings.from_task_fit.exists?
    import("task_fit_changes" => [ { "id" => "ac1", "status" => "met", "note" => "app/x.rb:40" } ])
    assert_equal "fits", @review.task_fit_verdict
    assert_equal "misses", @review.task_fit["verdict"]
    assert_equal({ "from" => "unmet", "to" => "met", "note" => "app/x.rb:40" }, @review.task_fit_reconciliation["changes"]["ac1"])
    assert_equal "fits", @review.task_fit_reconciliation["verdict"]
    assert_not @review.findings.from_task_fit.any? { |f| f.title.start_with?("AC niespełnione") }
  end

  test "kolejne uzgodnienie bez zmian przywraca oryginalne znaleziska zgodności" do
    import("task_fit_changes" => [ { "id" => "ac1", "status" => "met", "note" => "app/x.rb:40" } ])
    assert_not @review.findings.from_task_fit.any? { |f| f.title.start_with?("AC niespełnione") }
    import({})
    assert_nil @review.task_fit_reconciliation
    assert_equal "misses", @review.task_fit_verdict
    assert @review.findings.from_task_fit.any? { |f| f.title.start_with?("AC niespełnione") }
  end

  test "evidence_found z notatką zmienia werdykt i znaleziska przesłanki" do
    @review.update!(task_fit: @review.task_fit.merge("evidence_found" => false))
    TaskFitImporter.import(@review, "symptom" => "s", "assumed_cause" => "c", "evidence" => "e", "evidence_found" => false,
                                    "criteria" => [ { "id" => "ac1", "status" => "met", "note" => "." },
                                                    { "id" => "ac2", "status" => "met", "note" => "." } ])
    @review.reload
    assert_equal "misses", @review.task_fit_verdict
    assert @review.findings.from_task_fit.exists?
    import("evidence_found" => { "value" => true, "note" => "log z 21.08" })
    assert_equal({ "from" => false, "to" => true, "note" => "log z 21.08" }, @review.task_fit_reconciliation["evidence_found"])
    assert_equal "fits", @review.task_fit_verdict
    assert_not @review.findings.from_task_fit.exists?
  end

  test "zmiana punktu bez note albo z niedozwolonym statusem jest pomijana" do
    import("task_fit_changes" => [ { "id" => "ac1", "status" => "met", "note" => " " },
                                   { "id" => "ac1", "status" => "addressed", "note" => "dowód" },
                                   { "id" => "ac2", "status" => "met", "note" => "to samo" } ],
           "evidence_found" => { "value" => true, "note" => "to samo" })
    assert_nil @review.task_fit_reconciliation
    assert_equal "misses", @review.task_fit_verdict
    assert @review.findings.from_task_fit.exists?
  end

  test "summary nadpisane, raw_result bez zmian" do
    import("summary" => "nowe")
    assert_equal "nowe", @review.summary
    assert_equal '{"raw":true}', @review.raw_result
    import("summary" => "")
    assert_equal "nowe", @review.summary
  end

  test "call czyta reconcile.json" do
    File.write(@review.artifacts_dir.join("reconcile.json"), { summary: "z pliku" }.to_json)
    ReconcileResultImporter.call(@review, written_after: 1.minute.ago)
    assert_equal "z pliku", @review.reload.summary
  end

  test "brak pliku i stary plik dają Missing" do
    assert_raises(ReconcileResultImporter::Missing) { ReconcileResultImporter.call(@review) }
    path = @review.artifacts_dir.join("reconcile.json")
    File.write(path, "{}")
    File.utime(1.hour.ago.to_time, 1.hour.ago.to_time, path)
    assert_raises(ReconcileResultImporter::Missing) { ReconcileResultImporter.call(@review, written_after: Time.current) }
  end
end
