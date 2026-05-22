import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "orgCreatorsField",
    "creatorTemplate",
    "contributorTemplate",
    "funderTemplate",
    "materialTemplate",
    "creatorRow",
    "materialRow",
    "orcidDialog",
    "orcidFamilyName",
    "orcidGivenName",
    "orcidResults"
  ]

  connect() {
    this.activeOrcidRow = null
    this.orcidTriggerButton = null
    this.applyCreatorMode()
    this.syncPrimaryContact()
    this.materialRowTargets.forEach((row) => this.updateMaterialTypeVisibility(row))
    this.materialRowTargets.forEach((row) => this.syncDataciteListForRow(row))
    this.refreshAllRowPositions()
  }

  addCreatorRow() {
    this.addRowFromTemplate(this.creatorTemplateTarget, "creator-rows", "NEW_CREATOR")
    this.applyCreatorMode()
    this.syncPrimaryContact()
  }

  addContributorRow() {
    this.addRowFromTemplate(this.contributorTemplateTarget, "contributor-rows", "NEW_CONTRIBUTOR")
    this.refreshRowPositions("contributor-rows")
  }

  addFunderRow() {
    this.addRowFromTemplate(this.funderTemplateTarget, "funder-rows", "NEW_FUNDER")
    this.refreshRowPositions("funder-rows")
  }

  addMaterialRow() {
    this.addRowFromTemplate(this.materialTemplateTarget, "material-rows", "NEW_MATERIAL")
    this.refreshRowPositions("material-rows")
    const rows = this.element.querySelectorAll("[data-deposit-form-target='materialRow']")
    const newest = rows[rows.length - 1]
    if (newest) {
      this.updateMaterialTypeVisibility(newest)
      this.syncDataciteListForRow(newest)
    }
  }

  removeRow(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row) return

    const destroyField = row.querySelector("input[data-destroy-field]")
    const idField = row.querySelector("input[name$='[id]']")

    if (destroyField && idField && idField.value) {
      destroyField.value = "true"
      row.hidden = true
    } else {
      row.remove()
    }

    this.syncPrimaryContact()
    this.refreshAllRowPositions()
  }

  moveRowUp(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row) return

    const container = row.parentElement
    const visibleRows = Array.from(container.querySelectorAll(":scope > .idb-nested-row")).filter((item) => !item.hidden)
    const index = visibleRows.indexOf(row)
    if (index <= 0) return

    const previous = visibleRows[index - 1]
    container.insertBefore(row, previous)
    this.refreshContainerRowPositions(container)
  }

  moveRowDown(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row) return

    const container = row.parentElement
    const visibleRows = Array.from(container.querySelectorAll(":scope > .idb-nested-row")).filter((item) => !item.hidden)
    const index = visibleRows.indexOf(row)
    if (index < 0 || index >= visibleRows.length - 1) return

    const next = visibleRows[index + 1]
    container.insertBefore(next, row)
    this.refreshContainerRowPositions(container)
  }

  switchCreatorMode(event) {
    const mode = event.currentTarget.dataset.mode
    if (!this.hasOrgCreatorsFieldTarget) return

    this.orgCreatorsFieldTarget.value = mode === "institution" ? "true" : "false"
    this.applyCreatorMode()
    this.element.requestSubmit()
  }

  syncPrimaryContact() {
    const radios = this.element.querySelectorAll("input[type='radio'][name='primary_contact_index']")
    const selectedRadio = Array.from(radios).find((radio) => radio.checked)

    this.creatorRowTargets.forEach((row) => {
      const contact = row.querySelector("input[data-contact-field]")
      const isContact = row.querySelector("input[data-is-contact-field]")
      const rowRadio = row.querySelector("input[type='radio'][name='primary_contact_index']")
      const checked = !!(selectedRadio && rowRadio && selectedRadio === rowRadio)

      if (contact) contact.value = checked ? "true" : "false"
      if (isContact) isContact.value = checked ? "true" : "false"
    })
  }

  materialTypeChanged(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row) return
    this.updateMaterialTypeVisibility(row)
  }

  syncDataciteList(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row) return
    this.syncDataciteListForRow(row)
  }

  openOrcidLookup(event) {
    const row = event.currentTarget.closest(".idb-nested-row")
    if (!row || !this.hasOrcidDialogTarget) return

    this.activeOrcidRow = row
    this.orcidTriggerButton = event.currentTarget
    this.orcidResultsTarget.innerHTML = ""
    this.orcidFamilyNameTarget.value = row.querySelector("input[name*='[family_name]']")?.value || ""
    this.orcidGivenNameTarget.value = row.querySelector("input[name*='[given_name]']")?.value || ""
    this.orcidDialogTarget.showModal()
    this.orcidFamilyNameTarget.focus()
  }

  closeOrcidLookup() {
    if (!this.hasOrcidDialogTarget) return
    this.orcidDialogTarget.close()
  }

  onOrcidDialogCancel(event) {
    event.preventDefault()
    this.closeOrcidLookup()
  }

  onOrcidDialogClose() {
    this.activeOrcidRow = null
    if (this.orcidTriggerButton) {
      this.orcidTriggerButton.focus()
      this.orcidTriggerButton = null
    }
  }

  async searchOrcid() {
    if (!this.hasOrcidResultsTarget) return

    const familyName = this.orcidFamilyNameTarget.value.trim()
    const givenName = this.orcidGivenNameTarget.value.trim()

    if (!familyName && !givenName) {
      this.orcidResultsTarget.textContent = "Enter a family or given name to search."
      return
    }

    const baseUrl = this.element.dataset.orcidLookupUrl
    if (!baseUrl) {
      this.orcidResultsTarget.textContent = "Save the dataset draft before using ORCID lookup."
      return
    }

    const url = `${baseUrl}?family_name=${encodeURIComponent(familyName)}&given_name=${encodeURIComponent(givenName)}`

    this.orcidResultsTarget.textContent = "Searching..."

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      const payload = await response.json()

      if (!response.ok || !Array.isArray(payload.results)) {
        this.orcidResultsTarget.textContent = payload.error || "ORCID lookup unavailable."
        return
      }

      if (payload.results.length === 0) {
        this.orcidResultsTarget.textContent = "No ORCID results found."
        return
      }

      this.orcidResultsTarget.innerHTML = payload.results
        .map((result, idx) => {
          const label = this.escapeHtml(`${result.given_name || ""} ${result.family_name || ""}`.trim() || result.orcid)
          const institution = result.institution ? ` (${this.escapeHtml(result.institution)})` : ""
          const orcid = this.escapeHtml(result.orcid || "")
          const value = encodeURIComponent(JSON.stringify(result))
          return `<label><input type=\"radio\" name=\"orcid-choice\" value=\"${value}\" ${idx === 0 ? "checked" : ""}> ${label}${institution} - ${orcid}</label><br>`
        })
        .join("")
    } catch (_error) {
      this.orcidResultsTarget.textContent = "ORCID lookup unavailable."
    }
  }

  applyOrcidSelection() {
    if (!this.activeOrcidRow || !this.hasOrcidResultsTarget) return

    const selected = this.orcidResultsTarget.querySelector("input[name='orcid-choice']:checked")
    if (!selected) return

    const data = JSON.parse(decodeURIComponent(selected.value))
    this.setFieldValue(this.activeOrcidRow, "[family_name]", data.family_name)
    this.setFieldValue(this.activeOrcidRow, "[given_name]", data.given_name)
    this.setFieldValue(this.activeOrcidRow, "[identifier]", data.orcid)

    const orcidInput = this.activeOrcidRow.querySelector("input[data-orcid-field]")
    if (orcidInput) {
      orcidInput.value = data.orcid || ""
    }

    this.closeOrcidLookup()
  }

  addRowFromTemplate(templateTarget, containerId, token) {
    const container = this.element.querySelector(`#${containerId}`)
    if (!container) return

    const index = Date.now().toString()
    const html = templateTarget.innerHTML.replaceAll(token, index)
    container.insertAdjacentHTML("beforeend", html)
    this.refreshRowPositions(containerId)
  }

  applyCreatorMode() {
    const isOrgMode = this.hasOrgCreatorsFieldTarget && this.orgCreatorsFieldTarget.value === "true"

    this.creatorRowTargets.forEach((row) => {
      const personFields = row.querySelector("[data-creator-mode='person']")
      const orgFields = row.querySelector("[data-creator-mode='institution']")
      const typeField = row.querySelector("input[data-creator-type]")

      if (personFields) personFields.hidden = isOrgMode
      if (orgFields) orgFields.hidden = !isOrgMode
      if (typeField) typeField.value = isOrgMode ? "1" : "0"
    })
  }

  updateMaterialTypeVisibility(row) {
    const selected = row.querySelector("select[name*='[selected_type]']")
    const materialTypeField = row.querySelector("input[data-material-type-field]")
    if (!selected || !materialTypeField) return

    if (selected.value === "Other") {
      materialTypeField.hidden = false
      materialTypeField.required = true
      materialTypeField.focus()
    } else {
      materialTypeField.hidden = true
      materialTypeField.required = false
      materialTypeField.value = selected.value
    }
  }

  syncDataciteListForRow(row) {
    const listField = row.querySelector("input[data-datacite-list-field]")
    if (!listField) return

    const checked = Array.from(row.querySelectorAll("input[data-datacite-check]:checked")).map((checkbox) => checkbox.value)
    listField.value = checked.join(",")
  }

  refreshAllRowPositions() {
    this.refreshRowPositions("creator-rows")
    this.refreshRowPositions("contributor-rows")
    this.refreshRowPositions("funder-rows")
    this.refreshRowPositions("material-rows")
  }

  refreshRowPositions(containerId) {
    const container = this.element.querySelector(`#${containerId}`)
    if (!container) return
    this.refreshContainerRowPositions(container)
  }

  refreshContainerRowPositions(container) {
    const rows = Array.from(container.querySelectorAll(":scope > .idb-nested-row")).filter((row) => !row.hidden)
    rows.forEach((row, idx) => {
      const rowPosition = row.querySelector("input[name*='[row_position]']")
      const position = row.querySelector("input[name*='[position]']")
      if (rowPosition) rowPosition.value = idx + 1
      if (position) position.value = idx + 1
    })
  }

  setFieldValue(row, suffix, value) {
    const field = row.querySelector(`input[name*='${suffix}']`)
    if (field) field.value = value || ""
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;")
  }
}