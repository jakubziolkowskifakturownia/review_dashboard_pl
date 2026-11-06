# Wyciąga link do zadania z opisu PR-a. Konwencja zespołu: każdy PR ma zadanie
# podlinkowane w opisie, więc przepisywanie go ręcznie do formularza jest robotą
# do zera. Który z linków jest TYM zadaniem, rozstrzyga TaskLinkCheck.
#
# Wzorca nie zgadujemy — bierze się z `task_url_prefix` projektu. Dowolny URL byłby
# zły: w opisach są też linki do commitów, dokumentacji i innych PR-ów.
module TaskLink
  # Znaki, na których adres w opisie się kończy: markdown `[#32586](url)`, nawiasy,
  # przecinki i kropka na końcu zdania nie należą do adresu.
  TERMINATORS = %r{[\s)\]>,;"'`]}

  # Link z opisu z tym, co mówi o nim otoczenie: `subtask` — przed linkiem w tej
  # samej linii stoi „podzadanie”; `primary` — linia „PR dotyczy zadania:”.
  Candidate = Data.define(:url, :number, :subtask, :primary)

  def self.find(text, prefix:) = candidates(text, prefix: prefix).first&.url

  # Wszystkie linki do zadań w kolejności z opisu, po jednym na numer zadania
  # (`…/tasks/t/37148` i `…/tasks/37148` to to samo zadanie). Wskazówki z kolejnych
  # wzmianek tego samego zadania się sumują.
  def self.candidates(text, prefix:)
    return [] if text.blank? || prefix.blank?

    pattern = /#{Regexp.escape(prefix)}(?:(?!#{TERMINATORS.source}).)+/
    found = text.to_s.each_line.flat_map do |line|
      previous_end = 0
      line.to_enum(:scan, pattern).filter_map do
        match = Regexp.last_match
        before = line[previous_end...match.begin(0)]
        previous_end = match.end(0)
        url = match[0].sub(/\.\z/, "")
        number = number(url, prefix: prefix)
        number && Candidate.new(url: url, number: number, subtask: before.match?(/podzadani/i),
                                primary: line.match?(/dotyczy\s+zadania/i))
      end
    end
    found.group_by(&:number).map do |_, same|
      same.first.with(subtask: same.any?(&:subtask), primary: same.any?(&:primary))
    end
  end

  # Numer zadania widoczny w adresie (scoped_id), w obu formatach linków.
  def self.number(url, prefix:)
    from_prefix = prefix.present? ? url.to_s.delete_prefix(prefix)[%r{\A(?:t/)?(\d+)}, 1] : nil
    from_prefix || url.to_s[/(\d+)\D*\z/, 1]
  end
end
