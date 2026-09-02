import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["selectAll", "fileCheckbox", "deleteButton", "count"];

  connect() {
    this.updateState();
  }

  toggleSelectAll() {
    const checked = this.hasSelectAllTarget
      ? this.selectAllTarget.checked
      : false;
    this.fileCheckboxTargets.forEach((checkbox) => {
      checkbox.checked = checked;
    });
    this.updateState();
  }

  updateState() {
    const selectedCount = this.fileCheckboxTargets.filter(
      (checkbox) => checkbox.checked,
    ).length;

    if (this.hasDeleteButtonTarget) {
      this.deleteButtonTarget.disabled = selectedCount === 0;
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = `(${selectedCount})`;
    }

    if (this.hasSelectAllTarget) {
      const allSelected =
        this.fileCheckboxTargets.length > 0 &&
        selectedCount === this.fileCheckboxTargets.length;
      this.selectAllTarget.checked = allSelected;
      this.selectAllTarget.indeterminate = selectedCount > 0 && !allSelected;
    }
  }

  requestBulkDelete(event) {
    event.preventDefault();

    const selectedCount = this.fileCheckboxTargets.filter(
      (checkbox) => checkbox.checked,
    ).length;

    if (selectedCount === 0) {
      return;
    }

    const message =
      selectedCount === 1
        ? "Are you sure you want to delete this file metadata?"
        : `Are you sure you want to delete ${selectedCount} files? This action cannot be undone.`;

    if (confirm(message)) {
      this.element.querySelector("form")?.submit();
    }
  }
}
