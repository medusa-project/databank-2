import { Controller } from "@hotwired/stimulus";

// Resets header mobile menu state after every Turbo navigation.
// Prevents the drawer staying open when Turbo replaces <body> content.
export default class extends Controller {
  static MOBILE_BREAKPOINT = "(max-width: 991px)";

  connect() {
    document.addEventListener("turbo:load", this.resetMenu);
    this.watchHeaderState();
  }

  disconnect() {
    document.removeEventListener("turbo:load", this.resetMenu);
    if (this.headerObserver) {
      this.headerObserver.disconnect();
      this.headerObserver = null;
    }
  }

  resetMenu = () => {
    const header = document.querySelector("ilw-header, il-header");
    if (!header) {
      return;
    }

    // Keep desktop navigation expanded; only reset the mobile drawer state.
    if (!window.matchMedia(this.constructor.MOBILE_BREAKPOINT).matches) {
      this.enforceDesktopHeader(header);
      return;
    }

    if (typeof header.closeMenu === "function") {
      header.closeMenu();
      return;
    }

    if (header.tagName.toLowerCase() === "il-header") {
      header.expanded = false;
    }
  };

  watchHeaderState() {
    const header = document.querySelector("ilw-header, il-header");
    if (!header) {
      return;
    }

    this.enforceDesktopHeader(header);

    if (this.headerObserver) {
      this.headerObserver.disconnect();
    }

    this.headerObserver = new MutationObserver(() => {
      if (!window.matchMedia(this.constructor.MOBILE_BREAKPOINT).matches) {
        this.enforceDesktopHeader(header);
      }
    });

    this.headerObserver.observe(header, {
      attributes: true,
      attributeFilter: ["compact", "menu"],
    });
  }

  enforceDesktopHeader(header) {
    // Header components sometimes keep mobile/drawer state during navigation.
    // Remove those states so desktop always shows inline nav links.
    header.removeAttribute("compact");
    header.removeAttribute("menu");
    header.removeAttribute("expanded");
  }
}
