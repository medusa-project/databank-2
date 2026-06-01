import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "tokenValue", "pythonCommand", "curlCommand", "error"]
  static values = {
    currentUrl: String,
    renewUrl: String,
    datasetKey: String
  }

  open(event) {
    this.opener = event.currentTarget
    if (!this.hasDialogTarget) return

    this.dialogTarget.showModal()
    this.fetchToken(this.currentUrlValue)
  }

  close() {
    if (this.hasDialogTarget) {
      this.dialogTarget.close()
    }
  }

  onCancel(event) {
    event.preventDefault()
    this.close()
  }

  onClose() {
    if (this.opener) {
      this.opener.focus()
    }
  }

  renew() {
    this.fetchToken(this.renewUrlValue)
  }

  async fetchToken(url) {
    this.setError(null)
    this.updateToken("Loading...")

    try {
      const response = await fetch(url, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })

      if (!response.ok) {
        throw new Error("Could not fetch token")
      }

      const payload = await response.json()
      const token = payload.token
      this.updateToken(token)
      this.updateCommands(token)
    } catch (_error) {
      this.updateToken("Unavailable")
      this.updateCommands("[TOKEN]")
      this.setError("Could not fetch a token for this dataset.")
    }
  }

  updateToken(token) {
    if (this.hasTokenValueTarget) {
      this.tokenValueTarget.textContent = token
    }
  }

  updateCommands(token) {
    const datasetKey = this.datasetKeyValue
    const rootUrl = window.location.origin

    if (this.hasPythonCommandTarget) {
      this.pythonCommandTarget.textContent = `python databank_api_client_v2.py ${datasetKey} ${token} myfile.csv`
    }

    if (this.hasCurlCommandTarget) {
      this.curlCommandTarget.textContent = `curl -F "binary=@my_datafile.csv" -H "Authorization: Token token=${token}" -H "Transfer-Encoding: chunked" -X POST ${rootUrl}/api/dataset/${datasetKey}/datafile -o output.txt`
    }
  }

  setError(message) {
    if (!this.hasErrorTarget) return

    if (message) {
      this.errorTarget.hidden = false
      this.errorTarget.textContent = message
    } else {
      this.errorTarget.hidden = true
      this.errorTarget.textContent = ""
    }
  }
}