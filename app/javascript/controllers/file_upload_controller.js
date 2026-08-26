import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["dropZone", "fileInput"];

  connect() {
    this.dragCounter = 0;
  }

  selectFiles(event) {
    event.preventDefault();
    event.stopPropagation();
    this.fileInputTarget.click();
  }

  handleDragOver(event) {
    event.preventDefault();
    event.stopPropagation();
    this.dragCounter++;
    this.dropZoneTarget.classList.add("is-dragover");
  }

  handleDragOut(event) {
    event.preventDefault();
    event.stopPropagation();
    this.dragCounter--;
    if (this.dragCounter === 0) {
      this.dropZoneTarget.classList.remove("is-dragover");
    }
  }

  handleDrop(event) {
    event.preventDefault();
    event.stopPropagation();
    this.dragCounter = 0;
    this.dropZoneTarget.classList.remove("is-dragover");

    const files = event.dataTransfer.files;
    this.processFiles(files);
  }

  handleFileSelect(event) {
    const files = event.target.files;
    this.processFiles(files);
  }

  processFiles(files) {
    if (files.length === 0) return;

    // Create a FormData object with the files
    const formData = new FormData();
    Array.from(files).forEach((file) => {
      formData.append("datafiles[]", file);
    });

    // Get the dataset key from the URL
    const datasetKey =
      window.location.pathname.match(/\/datasets\/([^/]+)/)?.[1];

    if (!datasetKey) {
      this.showError("Unable to determine dataset. Please reload the page.");
      return;
    }

    const url = `/datasets/${datasetKey}/datafiles/bulk_create`;

    // Disable button during upload
    const uploadButton = this.dropZoneTarget.querySelector("button");
    if (uploadButton) uploadButton.disabled = true;

    fetch(url, {
      method: "POST",
      body: formData,
      headers: {
        "X-CSRF-Token": this.getCSRFToken(),
      },
    })
      .then((response) => response.json())
      .then((data) => {
        if (data.success || (data.count && data.count > 0)) {
          this.showSuccess(data.message);
          this.resetFileInput();
          // Reload the page after a short delay to show new files
          setTimeout(() => location.reload(), 1500);
        } else {
          this.showError(data.message || data.error);
          if (data.errors && data.errors.length > 0) {
            data.errors.forEach((error) => console.error(error));
          }
        }
      })
      .catch((error) => {
        console.error("Upload error:", error);
        this.showError(
          "An error occurred during file upload. Please try again.",
        );
      })
      .finally(() => {
        if (uploadButton) uploadButton.disabled = false;
      });
  }

  resetFileInput() {
    this.fileInputTarget.value = "";
  }

  getCSRFToken() {
    const token =
      document.querySelector('meta[name="csrf-token"]')?.content ||
      document.querySelector('[name="csrf-token"]')?.value;
    return token || "";
  }

  showSuccess(message) {
    this.showNotification(message, "success");
  }

  showError(message) {
    this.showNotification(message, "error");
  }

  showNotification(message, type) {
    // Create a notification element
    const notification = document.createElement("div");
    notification.className = `idb-notification idb-notification--${type}`;
    notification.textContent = message;
    notification.style.cssText = `
      position: fixed;
      top: 20px;
      right: 20px;
      z-index: 9999;
      padding: 1rem;
      border-radius: 0.375rem;
      max-width: 400px;
      box-shadow: 0 2px 8px rgba(0, 0, 0, 0.15);
      animation: slideIn 0.3s ease-in-out;
    `;

    if (type === "success") {
      notification.style.backgroundColor = "#d4edda";
      notification.style.color = "#155724";
      notification.style.border = "1px solid #c3e6cb";
    } else {
      notification.style.backgroundColor = "#f8d7da";
      notification.style.color = "#721c24";
      notification.style.border = "1px solid #f5c6cb";
    }

    document.body.appendChild(notification);

    // Auto-remove after 5 seconds
    setTimeout(() => {
      notification.style.animation = "slideOut 0.3s ease-in-out";
      setTimeout(() => notification.remove(), 300);
    }, 5000);
  }
}
