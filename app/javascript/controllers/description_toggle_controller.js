import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["remainder", "button"]
  static REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)"
  static values = {
    moreLabel: { type: String, default: "more description" },
    lessLabel: { type: String, default: "less description" }
  }

  async toggle() {
    const expanded = this.buttonTarget.getAttribute("aria-expanded") === "true"
    const nextExpanded = !expanded

    this.remainderTarget.getAnimations().forEach((animation) => animation.cancel())

    if (nextExpanded) {
      this.remainderTarget.hidden = false
      this.animateOpen()
    } else {
      await this.animateClose()
      this.remainderTarget.hidden = true
    }

    this.buttonTarget.setAttribute("aria-expanded", String(nextExpanded))
    this.buttonTarget.textContent = nextExpanded ? this.lessLabelValue : this.moreLabelValue
  }

  animateOpen() {
    if (window.matchMedia(this.constructor.REDUCED_MOTION_QUERY).matches) {
      return
    }

    this.remainderTarget.animate(
      [
        { opacity: 0, transform: "translateY(-0.15rem)" },
        { opacity: 1, transform: "translateY(0)" }
      ],
      {
        duration: 180,
        easing: "ease-out"
      }
    )
  }

  animateClose() {
    if (window.matchMedia(this.constructor.REDUCED_MOTION_QUERY).matches) {
      return Promise.resolve()
    }

    return this.remainderTarget.animate(
      [
        { opacity: 1, transform: "translateY(0)" },
        { opacity: 0, transform: "translateY(-0.1rem)" }
      ],
      {
        duration: 140,
        easing: "ease-in"
      }
    ).finished.catch(() => {})
  }
}