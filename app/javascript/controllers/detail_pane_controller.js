import { Controller } from "@hotwired/stimulus"

// Podświetlenie wybranej pozycji w lewej kolumnie. Bez niego po kilku kliknięciach
// nie widać, czyje szczegóły stoją po prawej — a kafle wyglądają identycznie.
// Wybór pamiętamy po id kafla, nie tylko klasą: broadcast idzie morphem, który
// nadpisuje atrybut class wersją z serwera, więc sama klasa gasła przy każdym
// sygnale z tła. Kafel, którego już nie ma, po prostu niczego nie podświetli.
const ITEM = ".qitem, .projcard, .archrow"

export default class extends Controller {
  connect() {
    this.element.addEventListener("click", this.pick)
    this.element.addEventListener("turbo:morph-element", this.reapply)
    this.restore()
  }

  disconnect() {
    this.element.removeEventListener("click", this.pick)
    this.element.removeEventListener("turbo:morph-element", this.reapply)
  }

  // Łapiemy klik w cokolwiek, co celuje w ramkę #detail — także w link „Zleć review",
  // nie tylko w tytuł kafla.
  pick = (event) => {
    const link = event.target.closest("a[data-turbo-frame='detail']")
    if (!link) return
    this.select(link.closest(ITEM))
  }

  // F5 albo link z czatu na adres z prawej ramki (/reviews/12): bez tego lewa kolumna
  // startuje od góry, bez zaznaczenia, i trzeba szukać kafla wzrokiem na długiej liście.
  restore() {
    const here = window.location.pathname + window.location.search
    const link = [...this.element.querySelectorAll("a[data-turbo-frame='detail']")].find((a) => {
      const url = new URL(a.href)
      return url.pathname + url.search === here
    })
    const item = link?.closest(ITEM)
    if (!item) return
    this.select(item)
    item.scrollIntoView({ block: "nearest" })
  }

  reapply = () => {
    if (!this.selectedId) return
    const item = document.getElementById(this.selectedId)
    if (item && !item.classList.contains("is-selected")) item.classList.add("is-selected")
  }

  select(item) {
    this.element.querySelectorAll(`${ITEM}.is-selected`).forEach((el) => el.classList.remove("is-selected"))
    this.selectedId = item?.id || null
    if (item) item.classList.add("is-selected")
  }
}
