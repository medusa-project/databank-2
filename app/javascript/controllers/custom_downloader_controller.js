import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal"]

  updateTotal() {
    const checkboxes = document.querySelectorAll('input[name="selected_files[]"]:checked')
    const button = document.getElementById("request-download-button")
    button.disabled = checkboxes.length === 0
  }

  requestDownload() {
    const checkboxes = document.querySelectorAll('input[name="selected_files[]"]:checked')
    const webIds = Array.from(checkboxes).map(cb => cb.value).join("~")

    if (!webIds) {
      alert("Please select at least one file")
      return
    }

    const datasetKey = document.querySelector("[data-dataset-key]")?.dataset.datasetKey
    if (!datasetKey) {
      console.error("Could not find dataset key")
      return
    }

    const button = document.getElementById("request-download-button")
    button.disabled = true
    button.textContent = "Generating download link..."

    fetch(`/datasets/${datasetKey}/download_link?web_ids=${encodeURIComponent(webIds)}`, {
      method: "GET",
      headers: {
        "Accept": "application/json"
      }
    })
      .then(response => response.json())
      .then(data => {
        button.disabled = false
        button.textContent = "Get Custom Zip and Download Link for Selected"

        if (data.status === "ok") {
          this.showDownloadLink(data.url, data.total_size)
        } else {
          alert(`Error: ${data.error || "Could not generate download link"}`)
        }
      })
      .catch(error => {
        button.disabled = false
        button.textContent = "Get Custom Zip and Download Link for Selected"
        console.error("Download request failed:", error)
        alert("Error requesting download link. Please try again.")
      })
  }

  showDownloadLink(url, totalSize) {
    const linkResult = document.getElementById("download-link-result")
    const fileSize = document.getElementById("download-file-size")
    const modal = document.getElementById("download-link-modal")

    if (linkResult) {
      linkResult.innerHTML = `<a href="${url}" target="_blank" rel="noopener">Click here to download your zip file</a>`
    }

    if (fileSize && totalSize) {
      const humanSize = this.formatBytes(totalSize)
      fileSize.textContent = `Total size: ${humanSize}`
    }

    if (modal) {
      modal.setAttribute("aria-hidden", "false")
      modal.style.display = "block"
    }
  }

  closeModal() {
    const modal = document.getElementById("download-link-modal")
    if (modal) {
      modal.setAttribute("aria-hidden", "true")
      modal.style.display = "none"
    }
  }

  formatBytes(bytes) {
    if (bytes === 0) return "0 bytes"

    const k = 1024
    const sizes = ["bytes", "KB", "MB", "GB"]
    const i = Math.floor(Math.log(bytes) / Math.log(k))

    return Math.round((bytes / Math.pow(k, i)) * 100) / 100 + " " + sizes[i]
  }
}
