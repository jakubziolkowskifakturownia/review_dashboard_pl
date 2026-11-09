# Wystawienie dashboardu przez tunel (cloudflared) — bramka na hasło + dozwolony host tunelu.
# Aktywne wyłącznie gdy ustawiony jest TUNNEL_PASSWORD; bez tej zmiennej nic się nie zmienia.
# Sama klasa jest definiowana zawsze, żeby testy mogły ją sprawdzić bez zmiennej.

# Basic auth odpadł, bo przeglądarki mobilne i wbudowane w komunikatory bywają, że nie
# pokazują promptu, a handshake WebSocketu i tak nie niesie nagłówka Authorization.
# Cookie leci z każdym żądaniem, też z /cable, więc jedna bramka chroni całość.
class TunnelGate
  COOKIE = "tunnel_key"
  LOCAL_HOSTS = %w[localhost 127.0.0.1 [::1]].freeze
  # Dokleja je proxy po drodze (Cloudflare zawsze), przeglądarka na tym Macu — nie.
  PROXY_HEADERS = %w[HTTP_X_FORWARDED_FOR HTTP_X_FORWARDED_HOST HTTP_FORWARDED HTTP_CF_CONNECTING_IP].freeze
  UNLOCK_PATH = "/unlock"
  UNLOCK_PREFIX = "#{UNLOCK_PATH}/"

  def initialize(app, password)
    @app = app
    # W cookie trzyma się pochodna hasła, żeby samo hasło nie leżało w przeglądarce.
    @token = Digest::SHA256.hexdigest("#{password}#{Rails.application.secret_key_base}")
    # Klucz z linku to sam heks — znaki specjalne z hasła nie przeżywają podróży przez
    # komunikatory i klawiatury mobilne.
    @link_key = @token.first(32)
    @password = password
  end

  def call(env)
    request = Rack::Request.new(env)

    return @app.call(env) if local?(env)
    return @app.call(env) if unlocked?(request)
    return grant(request) if correct_key?(key_from(request))

    reject(request)
  end

  private
    # Bez hasła wchodzi tylko ruch jawnie lokalny, cała reszta trafia na bramkę.
    # Nie request.host: Rack bierze go z X-Forwarded-Host/Forwarded, które ustawia klient.
    # Surowy Host plus brak nagłówków proxy — tych Cloudflare klientowi usunąć nie da.
    def local?(env)
      host = env["HTTP_HOST"].to_s.sub(/:\d+\z/, "")
      LOCAL_HOSTS.include?(host) && PROXY_HEADERS.none? { |header| env.key?(header) }
    end

    def unlocked?(request)
      secure_compare(request.cookies[COOKIE], @token)
    end

    # Trzy drogi wejścia: link `/unlock/<klucz>`, parametr `?k=`, formularz z ekranu bramki.
    def key_from(request)
      return request.path.delete_prefix(UNLOCK_PREFIX) if request.path.start_with?(UNLOCK_PREFIX)
      return request.POST["key"] if request.post? && request.path == UNLOCK_PATH

      request.GET["k"]
    end

    def correct_key?(candidate)
      secure_compare(candidate, @link_key) || secure_compare(candidate, @password)
    end

    # Bez tego odrzucenia są niewidoczne — bramka stoi przed logowaniem Railsów.
    def reject(request)
      Rails.logger.info(
        "[TunnelGate] 403 path=#{request.fullpath.inspect} cookie=#{request.cookies.key?(COOKIE)} ua=#{request.user_agent.inspect}"
      )

      # Formularz tylko dla nawigacji; żądania w tle (assety, WebSocket) dostają gołe 403.
      return [ 403, { "content-type" => "text/plain" }, [ "403 Forbidden\n" ] ] unless navigation?(request)

      [ 403, { "content-type" => "text/html; charset=utf-8", "cache-control" => "no-store" }, [ login_page ] ]
    end

    def navigation?(request)
      request.get? && request.get_header("HTTP_ACCEPT").to_s.include?("text/html")
    end

    def login_page
      <<~HTML
        <!DOCTYPE html>
        <html lang="pl">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Review Dashboard</title>
        <style>
          body { margin: 0; min-height: 100dvh; display: grid; place-items: center;
                 font: 16px/1.5 system-ui, sans-serif; background: #111; color: #eee; }
          form { display: grid; gap: 12px; width: min(320px, 88vw); }
          input, button { font: inherit; padding: 12px; border-radius: 10px; border: 1px solid #444; }
          input { background: #1c1c1c; color: #eee; }
          button { background: #2f6feb; color: #fff; border-color: #2f6feb; }
        </style>
        </head>
        <body>
        <form method="post" action="#{UNLOCK_PATH}">
          <input type="password" name="key" autocomplete="current-password"
                 autofocus autocapitalize="off" autocorrect="off" placeholder="Hasło">
          <button type="submit">Wejdź</button>
        </form>
        </body>
        </html>
      HTML
    end

    def secure_compare(candidate, expected)
      candidate.present? && ActiveSupport::SecurityUtils.secure_compare(candidate, expected)
    end

    # Hasło znika z adresu od razu po wejściu — w historii przeglądarki zostaje czysty URL.
    def grant(request)
      target = unlock_target(request)
      cookie = "#{COOKIE}=#{@token}; Path=/; Max-Age=#{1.year.to_i}; HttpOnly; Secure; SameSite=Lax"

      status = request.post? ? 303 : 302

      [ status, { "location" => target, "set-cookie" => cookie, "content-type" => "text/plain" }, [ "OK\n" ] ]
    end

    # Odblokowanie prowadzi na stronę główną; przy `?k=` zostaje ta sama ścieżka.
    def unlock_target(request)
      return "/" if request.path.start_with?(UNLOCK_PATH)

      params = request.GET.except("k")
      params.any? ? "#{request.path}?#{Rack::Utils.build_query(params)}" : request.path
    end
end

tunnel_password = ENV["TUNNEL_PASSWORD"].presence

if Rails.env.development? && tunnel_password
  Rails.application.configure do
    config.hosts << ".trycloudflare.com"
  end

  Rails.application.config.middleware.insert_before 0, TunnelGate, tunnel_password
end
