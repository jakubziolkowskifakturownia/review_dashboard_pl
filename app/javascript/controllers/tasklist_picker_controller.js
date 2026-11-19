import { Controller } from "@hotwired/stimulus"

// Pole listy zadań: użytkownik wybiera nazwę z datalisty, formularz wysyła id.
// Nazwa spoza podpowiedzi (literówka) nie zmienia wyboru — lepiej nic niż zła lista.
export default class extends Controller {
  static targets = ["input", "hidden"]

  pick() {
    const id = this.idFor(this.inputTarget.value)
    if (id === null && this.inputTarget.value.trim() !== "") return

    this.hiddenTarget.value = id ?? ""
    this.element.requestSubmit()
  }

  resolve(event) {
    const id = this.idFor(this.inputTarget.value)
    if (id === null && this.inputTarget.value.trim() !== "") event.preventDefault()
  }

  idFor(name) {
    const wanted = name.trim().toLowerCase()
    if (wanted === "") return ""

    const option = Array.from(this.inputTarget.list?.options ?? [])
      .find((candidate) => candidate.value.trim().toLowerCase() === wanted)
    return option ? option.dataset.id : null
  }
}
