import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submitButton", "warning"]

  connect() {
    this.updateUi()
  }

  handleOwnerYes() {
    this.updateUi()
  }

  handleOwnerNo() {
    this.updateUi()
  }

  handlePrivateYes() {
    this.updateUi()
  }

  handlePrivateNA() {
    this.updateUi()
  }

  handlePrivateNo() {
    this.updateUi()
  }

  handleAgreeYes() {
    this.updateUi()
  }

  handleAgreeNo() {
    this.updateUi()
  }

  updateUi() {
    if (this.allAnswersYes()) {
      this.allowSubmit()
      return
    }

    this.disableSubmit()
    if (this.hasAnyNoAnswer()) {
      this.showSelectionWarning()
    } else {
      this.clearSelectionWarning()
    }
  }

  allAnswersYes() {
    return this.checked("#owner-yes") && (this.checked("#private-yes") || this.checked("#private-na")) && this.checked("#agree-yes")
  }

  hasAnyNoAnswer() {
    return this.checked("#owner-no") || this.checked("#private-no") || this.checked("#agree-no")
  }

  allowSubmit() {
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = false
    this.clearSelectionWarning()
  }

  disableSubmit() {
    if (this.hasSubmitButtonTarget) this.submitButtonTarget.disabled = true
  }

  showSelectionWarning() {
    if (!this.hasWarningTarget) return

    const html =
      "<h2>Selection Alert</h2>" +
      "<p><span class='glyphicon glyphicon-alert'></span> " +
      "The selections you have made indicate that you are not ready to " +
      "deposit your dataset.</p>" +
      "<p>Illinois Data Bank curators are available to discuss your dataset " +
      "with you. Please <a href='/contact'>contact us</a>!</p>"

    this.warningTarget.innerHTML = html
  }

  clearSelectionWarning() {
    if (!this.hasWarningTarget) return
    this.warningTarget.innerHTML = ""
  }

  checked(selector) {
    const input = this.element.querySelector(selector)
    return !!(input && input.checked)
  }
}
