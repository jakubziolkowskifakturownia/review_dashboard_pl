# Broadcast to kosmetyka (odświeżenie strony pokaże stan) — jego błąd nie może
# wywracać logiki biznesowej ani boota (np. render przed załadowaniem routes).
module SafeBroadcasting
  extend ActiveSupport::Concern

  private

  def broadcast_safely(label)
    yield
  rescue StandardError => e
    Rails.logger.warn("#{label} dla #{self.class.name} #{id} nie powiódł się: #{e.class}: #{e.message}")
  end
end
