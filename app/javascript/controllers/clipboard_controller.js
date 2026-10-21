import { Controller } from "@hotwired/stimulus"

// Kopiuje treść pola do schowka. Fallback na zaznaczenie tekstu, bo Clipboard API
// działa tylko w bezpiecznym kontekście, a dashboard bywa otwierany przez tunel po http.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
      this.flash("Skopiowano ✓")
    } catch {
      this.sourceTarget.select()
      this.flash("Zaznaczone — Cmd+C")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = label
    setTimeout(() => { this.buttonTarget.textContent = original }, 2000)
  }
}
