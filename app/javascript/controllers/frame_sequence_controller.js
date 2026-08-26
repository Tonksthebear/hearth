import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "frame", "play", "pause" ]
  static values = { interval: Number }

  connect() {
    this.clearTimer()
    if (this.frameTargets.length < 2) return

    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.setPlaying(false)
      return
    }

    this.setPlaying(true)
    this.timer = window.setInterval(() => this.advance(), this.intervalValue)
  }

  disconnect() {
    this.clearTimer()
  }

  play() {
    if (this.element.dataset.playing === "true" && this.timer != null) return

    this.setPlaying(true)
    this.clearTimer()
    this.timer = window.setInterval(() => this.advance(), this.intervalValue)
  }

  pause() {
    if (this.element.dataset.playing === "false" && this.timer == null) return

    this.setPlaying(false)
    this.clearTimer()
  }

  previous() {
    this.pause()
    this.step(-1)
  }

  next() {
    this.pause()
    this.step(1)
  }

  advance() {
    this.step(1)
  }

  step(delta) {
    const frames = this.frameTargets
    if (frames.length < 2) return

    const currentIndex = frames.findIndex((frame) => !frame.hasAttribute("data-hidden"))
    const base = currentIndex < 0 ? 0 : currentIndex
    const nextIndex = (base + delta + frames.length) % frames.length

    frames.forEach((frame, index) => {
      frame.toggleAttribute("data-hidden", index !== nextIndex)
    })
  }

  setPlaying(playing) {
    this.element.dataset.playing = playing ? "true" : "false"
    if (this.hasPlayTarget) this.playTarget.setAttribute("aria-pressed", playing ? "true" : "false")
    if (this.hasPauseTarget) this.pauseTarget.setAttribute("aria-pressed", playing ? "false" : "true")
  }

  clearTimer() {
    if (this.timer != null) {
      window.clearInterval(this.timer)
      this.timer = null
    }
  }
}
