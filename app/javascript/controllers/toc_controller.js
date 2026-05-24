import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  navigate(event) {
    const link = event.target.closest("a[href^='#']")
    if (!link || !this.element.contains(link)) return

    const hash = link.getAttribute("href")
    if (!hash || hash === "#") return

    const targetId = decodeURIComponent(hash.slice(1))
    const target = document.getElementById(targetId)
    if (!target) return

    event.preventDefault()

    const prefersReducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    target.scrollIntoView({ behavior: prefersReducedMotion ? "auto" : "smooth", block: "start" })

    if (!target.hasAttribute("tabindex")) {
      target.setAttribute("tabindex", "-1")
    }
    target.focus({ preventScroll: true })

    history.replaceState(null, "", `#${targetId}`)
  }
}
