import { Controller } from "@hotwired/stimulus"

// Pole „dodaj listę zadań": użytkownik wybiera nazwę z datalisty, formularz dokłada
// jej id do już wybranych. Nazwa spoza podpowiedzi (literówka) nic nie wysyła.
export default class extends Controller {
  static targets = ["input", "hidden"]

  pick() {
    const id = this.idFor(this.inputTarget.value)
    if (!id) return

    this.hiddenTarget.value = id
    this.element.requestSubmit()
  }

  // Enter w polu: ten sam warunek co wybór z listy — bez trafionej nazwy nic nie idzie.
  resolve(event) {
    const id = this.idFor(this.inputTarget.value)
    if (!id) { event.preventDefault(); return }
    this.hiddenTarget.value = id
  }

  idFor(name) {
    const wanted = name.trim().toLowerCase()
    if (wanted === "") return ""

    const option = Array.from(this.inputTarget.list?.options ?? [])
      .find((candidate) => candidate.value.trim().toLowerCase() === wanted)
    return option ? option.dataset.id : null
  }
}
