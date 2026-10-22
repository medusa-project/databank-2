import { Controller } from "@hotwired/stimulus"

// Closes a <details> dropdown on Escape (returning focus to the summary) or on an outside click.
export default class extends Controller {
  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    this.onClick = this.onClick.bind(this)
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onClick)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onClick)
  }

  onKeydown(event) {
    if (event.key !== "Escape" || !this.element.open) return

    this.element.open = false
    this.element.querySelector("summary")?.focus()
  }

  onClick(event) {
    if (this.element.open && !this.element.contains(event.target)) {
      this.element.open = false
    }
  }
}
