import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.currentTargetId = null
    this.navLinks = Array.from(this.element.querySelectorAll("a[href^='#']"))
    this.targetRecords = this.navLinks
      .map((link) => {
        const hash = link.getAttribute("href")
        if (!hash || hash === "#") return null

        const targetId = decodeURIComponent(hash.slice(1))
        const target = document.getElementById(targetId)
        if (!target) return null

        return { link, targetId, target }
      })
      .filter(Boolean)

    this.boundHandleScroll = this.handleScroll.bind(this)
    window.addEventListener("scroll", this.boundHandleScroll, { passive: true })
    window.addEventListener("resize", this.boundHandleScroll)

    this.syncWithLocationHash()
    this.handleScroll()
  }

  disconnect() {
    window.removeEventListener("scroll", this.boundHandleScroll)
    window.removeEventListener("resize", this.boundHandleScroll)
  }

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
    const targetTop = target.getBoundingClientRect().top + window.scrollY - 16
    window.scrollTo({ top: targetTop, behavior: prefersReducedMotion ? "auto" : "smooth" })

    if (!target.hasAttribute("tabindex")) {
      target.setAttribute("tabindex", "-1")
    }
    target.focus({ preventScroll: true })

    this.markCurrentLink(link)
    history.replaceState(null, "", `#${targetId}`)
  }

  handleScroll() {
    if (!this.targetRecords?.length) return

    const activationOffset = 140
    let candidate = this.targetRecords[0]

    for (const record of this.targetRecords) {
      const top = record.target.getBoundingClientRect().top
      if (top <= activationOffset) {
        candidate = record
      } else {
        break
      }
    }

    if (candidate.targetId === this.currentTargetId) return
    this.markCurrentLink(candidate.link)
  }

  syncWithLocationHash() {
    const hash = window.location.hash
    if (!hash || hash === "#") return

    const targetId = decodeURIComponent(hash.slice(1))
    const record = this.targetRecords.find((item) => item.targetId === targetId)
    if (record) {
      this.markCurrentLink(record.link)
    }
  }

  markCurrentLink(activeLink) {
    this.element.querySelectorAll("a[aria-current='location']").forEach((anchor) => {
      anchor.removeAttribute("aria-current")
    })

    activeLink.setAttribute("aria-current", "location")
    this.currentTargetId = decodeURIComponent(activeLink.getAttribute("href").slice(1))
    this.scrollLinkIntoToc(activeLink)
  }

  scrollLinkIntoToc(link) {
    const container = this.element
    const linkTop = link.offsetTop
    const linkBottom = linkTop + link.offsetHeight
    const containerScrollTop = container.scrollTop
    const containerBottom = containerScrollTop + container.clientHeight

    if (linkTop < containerScrollTop) {
      container.scrollTop = linkTop - 8
    } else if (linkBottom > containerBottom) {
      container.scrollTop = linkBottom - container.clientHeight + 8
    }
  }
}
