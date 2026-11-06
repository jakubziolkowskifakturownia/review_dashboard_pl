# Rozstrzyga, który link z opisu PR-a prowadzi do zadania TEGO PR-a — i czy da się
# to potwierdzić. Pomyłka kosztuje dużo: bramka zgodności sprawdza AC z cudzego
# zadania, a komentarz po decyzji ląduje w złym miejscu trackera. Dlatego każda
# wątpliwość kończy się statusem `uncertain`, a ten blokuje oba kroki, dopóki
# człowiek nie potwierdzi zadania w panelu review.
#
# Kolejność wyboru: numer z tytułu PR-a („… (37148)”), link opisany jako
# „podzadanie”, linia „PR dotyczy zadania:”, pierwszy link. Tracker (gdy jest
# podpięty) dokłada jedno pytanie: czy wybrane zadanie nie jest zbiorcze — wtedy
# PR powinien wskazywać jego podzadanie.
class TaskLinkCheck
  Result = Data.define(:url, :status, :note)
  NONE = Result.new(url: nil, status: nil, note: nil)
  TITLE_NUMBER = /\((\d{3,7})\)/
  # Próg podobieństwa tytułów (Dice na słowach), od którego PR „wygląda na” podzadanie.
  SIMILAR = 0.6

  def initialize(prefix:, intum: nil)
    @prefix = prefix
    @intum = intum
  end

  def call(title:, body:)
    return NONE if @prefix.blank?

    candidates = TaskLink.candidates(body, prefix: @prefix)
    title_number = title.to_s[TITLE_NUMBER, 1]
    return from_title_only(title_number) if candidates.empty?

    pick, how = choose(candidates, title_number)
    problems = []
    if @intum
      checked = verify_in_tracker(pick, candidates, title, problems)
      how = :tracker if checked != pick
      pick = checked
    end
    if title_number && pick.number != title_number
      problems << "Tytuł PR-a wskazuje ##{title_number}, a link w opisie prowadzi do ##{pick.number}."
    elsif how == :first && candidates.size > 1
      problems << "W opisie jest kilka zadań (#{candidates.map { |c| "##{c.number}" }.join(", ")}) — wybrałem pierwsze."
    end
    Result.new(url: pick.url, status: problems.empty? ? "confirmed" : "uncertain", note: problems.join(" ").presence)
  end

  private

  def from_title_only(number)
    return NONE unless number

    Result.new(url: "#{@prefix}#{number}", status: "uncertain",
               note: "W opisie PR-a nie ma linku do zadania — numer ##{number} jest wzięty z tytułu PR-a.")
  end

  def choose(candidates, title_number)
    if (by_title = candidates.find { |c| c.number == title_number }) then [ by_title, :title ]
    elsif (subtask = candidates.find(&:subtask)) then [ subtask, :subtask ]
    elsif (primary = candidates.find(&:primary)) then [ primary, :primary ]
    else [ candidates.first, :first ]
    end
  end

  # Podzadania w trackerze bywają poboczne („do analizy”, „projekt graficzny”), więc
  # samo ich istnienie nic nie mówi. Mówią dwie rzeczy: link do jednego z nich w opisie
  # (bierzemy je) albo tytuł PR-a wyraźnie bliższy podzadaniu niż rodzicowi — wtedy
  # PR wskazuje zadanie nadrzędne zamiast swojego i nie zgadujemy.
  def verify_in_tracker(pick, candidates, title, problems)
    parent = @intum.task(pick.number)
    children = @intum.subtasks(parent.fetch("id"))
    return pick if children.empty?

    linked = candidates.select { |c| children.any? { |child| child["scoped_id"].to_s == c.number } }
    return linked.sole if linked.one?
    if linked.many?
      problems << "##{pick.number} ma kilka podzadań podlinkowanych w opisie (#{linked.map { |c| "##{c.number}" }.join(", ")})."
      return pick
    end

    best = children.max_by { |child| similarity(title, child["title"]) }
    if similarity(title, best["title"]) >= SIMILAR && similarity(title, best["title"]) > similarity(title, parent["title"])
      problems << "Link prowadzi do ##{pick.number}, a tytuł PR-a pasuje do jego podzadania ##{best["scoped_id"]} " \
                  "„#{best["title"]}”: #{@prefix}#{best["scoped_id"]}"
    end
    pick
  rescue IntumClient::Error, KeyError => e
    problems << "Nie udało się sprawdzić zadania ##{pick.number} w trackerze (#{e.message})."
    pick
  end

  # Dice na zbiorach słów (≥3 litery), bez tagów w nawiasach kwadratowych i numerów
  # zadań: „[ALL] Eksport faktur … (123)” i „[API] Eksport faktur …” mają być tym samym.
  def similarity(a, b)
    words_a, words_b = words(a), words(b)
    return 0.0 if words_a.empty? || words_b.empty?

    2.0 * (words_a & words_b).size / (words_a.size + words_b.size)
  end

  def words(text)
    text.to_s.downcase.gsub(/\[[^\]]*\]|\(\d+\)/, " ").scan(/[[:alpha:]_*]{3,}/).uniq
  end
end
