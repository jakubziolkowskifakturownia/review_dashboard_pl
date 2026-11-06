require "test_helper"

class TaskLinkCheckTest < ActiveSupport::TestCase
  PREFIX = "https://tracker.example.com/organize/tasks/"

  # Fake trackera: zadania po numerze, podzadania po PK rodzica.
  class FakeIntum
    def initialize(tasks: {}, children: {}, fail: false)
      @tasks = tasks
      @children = children
      @fail = fail
    end

    def task(number)
      raise IntumClient::Error, "tracker leży" if @fail

      @tasks.fetch(number.to_s) { { "id" => "pk#{number}", "scoped_id" => number.to_i } }
    end

    # Podzadanie: numer albo [numer, tytuł].
    def subtasks(pk)
      Array(@children[pk]).map do |number, title|
        { "scoped_id" => number, "task_id" => pk, "title" => title || "Podzadanie #{number}" }
      end
    end
  end

  def check(title:, body:, intum: nil) = TaskLinkCheck.new(prefix: PREFIX, intum: intum).call(title: title, body: body)

  test "jeden link i tytuł z tym samym numerem: potwierdzone" do
    result = check(title: "[ALL] Eksport raportu do CSV (37148)", body: "Zadanie: #{PREFIX}t/37148", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}t/37148", "confirmed", nil ], [ result.url, result.status, result.note ]
  end

  test "bez linku i bez numeru w tytule nie ma czego sprawdzać" do
    result = check(title: "Poprawka", body: "brak zadania")
    assert_nil result.url
    assert_nil result.status
  end

  test "numer z tytułu wygrywa z pierwszym linkiem w opisie" do
    result = check(title: "[ALL] Logowanie zdarzeń (37294)",
                   body: "Wdrożenie: #{PREFIX}37293\nZadanie: #{PREFIX}t/37294", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}t/37294", "confirmed" ], [ result.url, result.status ]
  end

  # Częsta konwencja: „Zadanie: <zbiorcze> (podzadanie <właściwe>)".
  test "podzadanie wskazane w opisie wygrywa z zadaniem zbiorczym" do
    intum = FakeIntum.new(children: { "pk37328" => [ 37893, 37894 ] })
    result = check(title: "[ALL] Import kontaktów z pliku",
                   body: "**Zadanie:** #{PREFIX}37328 (podzadanie: #{PREFIX}t/37893)", intum: intum)
    assert_equal [ "#{PREFIX}t/37893", "confirmed" ], [ result.url, result.status ]
  end

  test "link do zadania nadrzędnego, a tytuł PR-a pasuje do podzadania: niepewne z podpowiedzią" do
    intum = FakeIntum.new(tasks: { "37328" => { "id" => "pk37328", "title" => "Porządki w kontrolerach — zbiorcze" } },
                          children: { "pk37328" => [ [ 37893, "Import kontaktów z pliku CSV" ],
                                                     [ 37892, "Eksport faktur: filtr po dacie i walucie, tylko POST" ] ] })
    result = check(title: "[ALL] Eksport faktur: filtr po dacie, walucie i statusie, tylko POST",
                   body: "Zadanie: #{PREFIX}37328", intum: intum)
    assert_equal [ "#{PREFIX}37328", "uncertain" ], [ result.url, result.status ]
    assert_match "#{PREFIX}37892", result.note
  end

  # Podzadania bywają poboczne (analiza, grafika) — samo ich istnienie nie budzi wątpliwości.
  test "zadanie z pobocznymi podzadaniami i tytułem PR-a o czymś innym: potwierdzone" do
    intum = FakeIntum.new(tasks: { "34745" => { "id" => "pk34745", "title" => "Błąd w sumach na raporcie miesięcznym" } },
                          children: { "pk34745" => [ [ 35211, "Raporty - do analizy czy potrzebujemy zmiany" ] ] })
    result = check(title: "[ALL] Raport miesięczny: zaokrąglenia sum", body: "#{PREFIX}34745", intum: intum)
    assert_equal "confirmed", result.status
  end

  test "zbiorcze bez słowa „podzadanie”, ale z linkiem do jednego z jego podzadań: bierze podzadanie" do
    intum = FakeIntum.new(children: { "pk37328" => [ 37893 ] })
    result = check(title: "Fix", body: "#{PREFIX}37328 i #{PREFIX}37893", intum: intum)
    assert_equal [ "#{PREFIX}37893", "confirmed" ], [ result.url, result.status ]
  end

  test "numer w tytule bez linku w opisie: niepewne" do
    result = check(title: "Fix (555)", body: "Zadanie: #{PREFIX}444", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}444", "uncertain" ], [ result.url, result.status ]
    assert_match "#555", result.note
  end

  test "sam numer w tytule bez żadnego linku: link z numeru, ale niepewne" do
    result = check(title: "Fix (555)", body: "", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}555", "uncertain" ], [ result.url, result.status ]
  end

  test "linia „PR dotyczy zadania” wygrywa z innymi wzmiankami" do
    result = check(title: "Fix", intum: FakeIntum.new,
                   body: "- [x] PR dotyczy zadania: #{PREFIX}37959\n\nta sama klasa co [#37909](#{PREFIX}37909)")
    assert_equal [ "#{PREFIX}37959", "confirmed" ], [ result.url, result.status ]
  end

  test "kilka różnych zadań bez żadnej wskazówki: niepewne" do
    result = check(title: "Fix", body: "#{PREFIX}1 oraz #{PREFIX}2", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}1", "uncertain" ], [ result.url, result.status ]
  end

  test "ten sam numer w obu formatach to jedno zadanie" do
    result = check(title: "Fix", body: "#{PREFIX}t/37148 i jeszcze raz #{PREFIX}37148", intum: FakeIntum.new)
    assert_equal [ "#{PREFIX}t/37148", "confirmed" ], [ result.url, result.status ]
  end

  test "padnięty tracker: niepewne, bo nic nie sprawdziliśmy" do
    result = check(title: "Fix (7)", body: "#{PREFIX}7", intum: FakeIntum.new(fail: true))
    assert_equal "uncertain", result.status
    assert_match "tracker leży", result.note
  end
end
