import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["name", "identifier"]
  static values = {
    identifiers: Object
  }

  connect() {
    this.syncIdentifier()
  }

  syncIdentifier() {
    const identifier = this.identifiersValue[this.nameTarget.value]
    return if !identifier

    this.identifierTarget.value = identifier
  }
}