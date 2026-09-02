import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "dropZone",
    "fileInput",
    "progressContainer",
    "progressBar",
    "progressFill",
    "percentageText",
    "statusText",
    "cancelButton",
  ];

  connect() {
    this.dragCounter = 0;
    this.activeXhr = null;
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

  cancelUpload(event) {
    if (event) {
      event.preventDefault();
      event.stopPropagation();
    }
    if (this.activeXhr) {
      this.activeXhr.abort();
      this.activeXhr = null;
    }
  }

  processFiles(files) {
    if (!files || files.length === 0) return;

    const fileList = Array.from(files);
    const fileCount = fileList.length;
    const totalBytes = fileList.reduce((acc, f) => acc + (f.size || 0), 0);

    // Create a FormData object with the files
    const formData = new FormData();
    fileList.forEach((file) => {
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

    // Disable upload button during upload
    const uploadButton = this.dropZoneTarget.querySelector("button");
    if (uploadButton) uploadButton.disabled = true;

    // Reveal and initialize progress container if available
    this.startProgressUI(fileCount, totalBytes);

    const xhr = new XMLHttpRequest();
    this.activeXhr = xhr;

    xhr.open("POST", url, true);
    xhr.setRequestHeader("X-CSRF-Token", this.getCSRFToken());

    if (xhr.upload) {
      xhr.upload.addEventListener("progress", (event) => {
        if (event.lengthComputable) {
          const percent = Math.round((event.loaded / event.total) * 100);
          this.updateProgressUI(percent, event.loaded, event.total, fileCount);
        }
      });
    }

    xhr.onload = () => {
      this.activeXhr = null;
      let data = null;
      try {
        data = JSON.parse(xhr.responseText);
      } catch (e) {
        console.error("Failed to parse JSON response:", e);
      }

      if (xhr.status >= 200 && xhr.status < 300 && data) {
        if (data.success || (data.count && data.count > 0)) {
          this.completeProgressUI(data.message || "Upload completed!");
          this.showSuccess(data.message);
          this.resetFileInput();
          setTimeout(() => location.reload(), 1500);
          return;
        }
      }

      const errorMessage =
        (data && (data.message || data.error)) ||
        "An error occurred during file upload. Please try again.";
      this.errorProgressUI(errorMessage);
      this.showError(errorMessage);
      if (uploadButton) uploadButton.disabled = false;
    };

    xhr.onerror = () => {
      this.activeXhr = null;
      const msg =
        "Network error occurred during file upload. Please check your connection.";
      this.errorProgressUI(msg);
      this.showError(msg);
      if (uploadButton) uploadButton.disabled = false;
    };

    xhr.onabort = () => {
      this.activeXhr = null;
      this.abortProgressUI();
      this.showError("Upload was canceled.");
      if (uploadButton) uploadButton.disabled = false;
      this.resetFileInput();
    };

    xhr.send(formData);
  }

  startProgressUI(fileCount, totalBytes) {
    if (!this.hasProgressContainerTarget) return;

    this.progressContainerTarget.hidden = false;
    if (this.hasProgressFillTarget) {
      this.progressFillTarget.style.width = "0%";
      this.progressFillTarget.classList.remove(
        "idb-progress-fill--success",
        "idb-progress-fill--error",
      );
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.setAttribute("aria-valuenow", "0");
    }
    if (this.hasPercentageTextTarget) {
      this.percentageTextTarget.textContent = "0%";
    }
    if (this.hasStatusTextTarget) {
      const fileLabel = fileCount === 1 ? "1 file" : `${fileCount} files`;
      this.statusTextTarget.textContent = `Uploading ${fileLabel} (0 B of ${this.formatBytes(totalBytes)})...`;
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = false;
      this.cancelButtonTarget.hidden = false;
    }
  }

  updateProgressUI(percent, loadedBytes, totalBytes, fileCount) {
    if (!this.hasProgressContainerTarget) return;

    if (this.hasProgressFillTarget) {
      this.progressFillTarget.style.width = `${percent}%`;
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.setAttribute("aria-valuenow", percent.toString());
    }
    if (this.hasPercentageTextTarget) {
      this.percentageTextTarget.textContent = `${percent}%`;
    }
    if (this.hasStatusTextTarget) {
      const fileLabel = fileCount === 1 ? "1 file" : `${fileCount} files`;
      this.statusTextTarget.textContent = `Uploading ${fileLabel}: ${this.formatBytes(loadedBytes)} of ${this.formatBytes(totalBytes)}`;
    }
  }

  completeProgressUI(message) {
    if (!this.hasProgressContainerTarget) return;

    if (this.hasProgressFillTarget) {
      this.progressFillTarget.style.width = "100%";
      this.progressFillTarget.classList.add("idb-progress-fill--success");
      this.progressFillTarget.classList.remove("idb-progress-fill--error");
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.setAttribute("aria-valuenow", "100");
    }
    if (this.hasPercentageTextTarget) {
      this.percentageTextTarget.textContent = "100%";
    }
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = "Upload complete! Processing...";
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true;
    }
  }

  errorProgressUI(message) {
    if (!this.hasProgressContainerTarget) return;

    if (this.hasProgressFillTarget) {
      this.progressFillTarget.classList.add("idb-progress-fill--error");
      this.progressFillTarget.classList.remove("idb-progress-fill--success");
    }
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = "Upload failed.";
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true;
    }
  }

  abortProgressUI() {
    if (!this.hasProgressContainerTarget) return;

    if (this.hasProgressFillTarget) {
      this.progressFillTarget.style.width = "0%";
      this.progressFillTarget.classList.remove(
        "idb-progress-fill--success",
        "idb-progress-fill--error",
      );
    }
    if (this.hasProgressBarTarget) {
      this.progressBarTarget.setAttribute("aria-valuenow", "0");
    }
    if (this.hasPercentageTextTarget) {
      this.percentageTextTarget.textContent = "0%";
    }
    if (this.hasStatusTextTarget) {
      this.statusTextTarget.textContent = "Upload canceled.";
    }
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true;
    }
  }

  formatBytes(bytes) {
    if (bytes === 0 || !bytes) return "0 B";
    const k = 1024;
    const sizes = ["B", "KB", "MB", "GB", "TB"];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
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
