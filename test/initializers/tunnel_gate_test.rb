require "test_helper"

class TunnelGateTest < ActiveSupport::TestCase
  PASSWORD = "haslo-testowe"

  def gate
    TunnelGate.new(->(_env) { [ 200, {}, [ "dashboard" ] ] }, PASSWORD)
  end

  def status_for(headers)
    gate.call(Rack::MockRequest.env_for("/", { "HTTP_ACCEPT" => "text/html" }.merge(headers))).first
  end

  # Tak wygląda żądanie po przejściu przez cloudflared: host tunelu plus nagłówki,
  # które dokleja Cloudflare — klient z internetu nie ma jak ich usunąć.
  def from_tunnel(extra = {})
    { "HTTP_HOST" => "demo.trycloudflare.com",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.7",
      "HTTP_CF_CONNECTING_IP" => "203.0.113.7" }.merge(extra)
  end

  test "should let local requests through without a password" do
    assert_equal 200, status_for("HTTP_HOST" => "localhost:3020")
    assert_equal 200, status_for("HTTP_HOST" => "127.0.0.1:3020")
  end

  test "should reject a tunnel request without the key" do
    assert_equal 403, status_for(from_tunnel)
  end

  # request.host w Racku bierze wartość z nagłówków przekazywania, a te ustawia klient.
  # Decyzja „lokalne czy z sieci" nie może na nich polegać.
  test "should not treat forwarded host headers as a local request" do
    assert_equal 403, status_for(from_tunnel("HTTP_X_FORWARDED_HOST" => "localhost"))
    assert_equal 403, status_for(from_tunnel("HTTP_FORWARDED" => "host=localhost"))
  end

  # cloudflared umie przepisać Host na localhost (httpHostHeader) — bramka ma wtedy
  # nadal działać, a nie wyłączyć się po cichu.
  test "should still require the key when the proxy rewrites the host to localhost" do
    assert_equal 403, status_for(from_tunnel("HTTP_HOST" => "localhost:3020"))
  end

  test "should let a tunnel request with the unlock cookie through" do
    token = Digest::SHA256.hexdigest("#{PASSWORD}#{Rails.application.secret_key_base}")

    assert_equal 200, status_for(from_tunnel("HTTP_COOKIE" => "tunnel_key=#{token}"))
  end
end
