import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["kind", "fields", "template", "applicable"]
  static values = { kind: String }

  connect() {
    this.render()
  }

  kindValueChanged() {
    if (this.element.isConnected) this.render()
  }

  change() {
    this.render()
  }

  render() {
    const kind = this.currentKind
    if (!kind) return

    if (this.hasFieldsTarget) {
      const template = this.templateTargets.find((candidate) => candidate.dataset.kind === kind)
      this.fieldsTarget.replaceChildren(template ? template.content.cloneNode(true) : "")
    }

    this.applicableTargets.forEach((wrapper) => {
      const active = wrapper.dataset.kinds.split(" ").includes(kind)
      wrapper.toggleAttribute("data-hidden", !active)
      wrapper.querySelectorAll("input, select, textarea, button, el-select, el-autocomplete").forEach((control) => {
        control.toggleAttribute("disabled", !active)
        control.disabled = !active
      })
    })

    this.element.querySelectorAll('[data-controller~="performance-fields"][data-performance-fields-kind-value]').forEach((child) => {
      if (child !== this.element) child.dataset.performanceFieldsKindValue = kind
    })
  }

  get currentKind() {
    return this.hasKindTarget ? (this.kindTarget.value || this.kindTarget.getAttribute("value")) : this.kindValue
  }
}
