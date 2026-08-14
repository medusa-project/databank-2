import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  submitOnChange(event) {
    if (!(event.target instanceof HTMLInputElement)) {
      return;
    }

    if (!event.target.classList.contains("facet-checkbox")) {
      return;
    }

    this.element.requestSubmit();
  }
}
