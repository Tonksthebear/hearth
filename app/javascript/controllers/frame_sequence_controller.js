import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = { interval: Number }

  connect() {
    this.clearTimer()
    if (this.frameTargets.length < 2) return

    this.timer = window.setInterval(() => this.advance(), this.intervalValue)
  }

  disconnect() {
    this.clearTimer()
  }

  advance() {
    const frames = this.frameTargets
    const currentIndex = frames.findIndex((frame) => !frame.hasAttribute("data-hidden"))
    const nextIndex = ((currentIndex < 0 ? 0 : currentIndex) + 1) % frames.length

    frames.forEach((frame, index) => {
      frame.toggleAttribute("data-hidden", index !== nextIndex)
    })
  }

  clearTimer() {
    if (this.timer != null) {
      window.clearInterval(this.timer)
      this.timer = null
    }
  }
}
