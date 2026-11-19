require "net/http"

# Cienki klient API trackera (Intum/Sugester) — token per projekt, autoryzacja
# przez ?api_token=. Tracker odrzuca requesty bez przeglądarkowego User-Agenta
# (403 bez treści), stąd wymuszony UA. Zapisy (komentarz) nie wymagają CSRF —
# w przeciwieństwie do ścieżki cookie, którą ten klient zastępuje.
class IntumClient
  Error = Class.new(StandardError)

  USER_AGENT = "Mozilla/5.0 (Macintosh) AppleWebKit/537.36".freeze
  MAX_USER_PAGES = 30 # bezpiecznik pętli paginacji (tracker zwraca po ~500 osób na stronę)

  def initialize(base_url:, token:, transport: nil)
    @base_url = base_url
    @token = token
    @transport = transport || HttpTransport.new(base_url)
  end

  # Zespół do comboboxa drugiego sprawdzenia. Konto trackera ma tysiące gości
  # (klientów) — zostają aktywni nie-goście. Ról nie whitelistujemy: bywają
  # numerycznymi ID custom ról jako stringi (np. "1089"). API trackera nie
  # przyjmuje filtrów roli/aktywności, stąd selekcja po naszej stronie.
  # `limit_pages: 1` = tani test połączenia (jedna strona zamiast całości).
  def users(limit_pages: MAX_USER_PAGES)
    team = []
    (1..limit_pages).each do |page|
      batch = parse(@transport.get("/account/users.json", { page: page, api_token: @token }))
      team.concat(batch.select { |u| u["active"] && u["role"] != "guest" }
                       .map { |u| { "id" => u["user_id"].to_s, "name" => u["get_name"] } })
      break if batch.empty?
    end
    team
  end

  # Zadanie po numerze z URL-a (scoped_id). Zwraca m.in. "id" — PK, którego
  # wymagają zapisy (komentarze chodzą po PK, nie po numerze z URL-a).
  def task(scoped_id)
    parse(@transport.get("/organize/tasks/#{scoped_id}.json", { api_token: @token }))
  end

  # Podzadania zadania o danym PK (pole `task_id` podzadania to PK rodzica). Filtr
  # powtarzamy u siebie: gdyby tracker kiedyś zignorował parametr, oddałby pierwszą
  # stronę wszystkich zadań i każde zadanie wyglądałoby na zbiorcze.
  def subtasks(task_pk)
    parse(@transport.get("/organize/tasks.json", { task_id: task_pk, api_token: @token }))
      .select { |task| task["task_id"].to_s == task_pk.to_s }
  end

  # Listy zadań, na których leży zadanie (cykl, backlog, incydent…). JSON zadania
  # ich nie zwraca, a filtr `tasks.json?tasklist_ids[]=` działa tylko w drugą stronę
  # (lista → zadania, setki list) — jedynym źródłem jest strona HTML zadania.
  # Zmiana HTML-a trackera skończy się pustą tablicą, nie wyjątkiem: chipy znikną,
  # dashboard dalej działa.
  def task_lists(scoped_id)
    # `/t/<numer>`: pod `/organize/tasks/<numer>` przeglądarkowy Accept dostaje 301 właśnie tutaj.
    response = @transport.get_html("/organize/tasks/t/#{scoped_id}", bearer: @token)
    unless response.code.to_i.between?(200, 299)
      raise Error, "tracker odpowiedział #{response.code} na stronę zadania ##{scoped_id}"
    end

    # Tracker renderuje każdy chip dwa razy (wersja szeroka i wąska) — stąd uniq.
    Nokogiri::HTML(response.body).css("a[id^='task_tasklist_'][id$='_small']").filter_map do |link|
      id = link["id"][/\Atask_tasklist_(\d+)_small\z/, 1]
      # Nazwa z tekstu chipa: `title` ma doklejony rodzaj listy („Lista …”, „Cykl …”,
      # „Sprint …”), a tekst tylko znacznik ✓ i twardą spację.
      name = link.text.gsub(/[✓\u00a0]/, " ").squish.presence || link.parent["title"].to_s.delete_prefix("Lista ").strip
      { "id" => id, "name" => name, "url" => link["href"].to_s } if id && name.present?
    end.uniq { |list| list["id"] }
  end

  def post_comment(task_pk, content, responsible_id: nil)
    form = { "comment[commentable_id]" => task_pk,
             "comment[commentable_type]" => "Organize::Task",
             "comment[content]" => content,
             "comment[config][markup_lang]" => "github_markdown" }
    form["comment[responsible_id]"] = responsible_id if responsible_id.present?
    parse(@transport.post("/organize/comments.json", { api_token: @token }, form))
  end

  private

  def parse(response)
    unless response.code.to_i.between?(200, 299)
      raise Error, "tracker odpowiedział #{response.code}: #{response.body.to_s.truncate(200)}"
    end

    JSON.parse(response.body)
  rescue JSON::ParserError
    raise Error, "tracker zwrócił nie-JSON (#{response.code})"
  end

  # Realny transport — w testach podmieniany fake'iem o tym samym kształcie.
  class HttpTransport
    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 15

    def initialize(base_url)
      @base_url = base_url
    end

    def get(path, params)
      request(Net::HTTP::Get.new(url(path, params)))
    end

    # Strona HTML przyjmuje token wyłącznie jako Bearer — `?api_token=` daje tu 401.
    def get_html(path, bearer:)
      req = Net::HTTP::Get.new(URI.join(@base_url, path))
      req["Authorization"] = "Bearer #{bearer}"
      request(req, accept: "text/html")
    end

    def post(path, params, form)
      req = Net::HTTP::Post.new(url(path, params))
      req.set_form_data(form)
      request(req)
    end

    private

    def url(path, params)
      URI.join(@base_url, path).tap { |u| u.query = URI.encode_www_form(params) }
    end

    def request(req, accept: "application/json")
      req["User-Agent"] = USER_AGENT
      req["Accept"] = accept
      uri = req.uri
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                      open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
        http.request(req)
      end
    # SocketError osobno: błąd DNS (zły host w prefiksie zadań) dziedziczy ze
    # StandardError, nie z SystemCallError — bez niego wyciekałby poza Error.
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Error, "połączenie z trackerem nie powiodło się: #{e.message}"
    end
  end
end
