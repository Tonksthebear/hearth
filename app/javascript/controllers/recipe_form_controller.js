import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["ingredientName", "ingredientReference"]

  ingredientNameChanged() {
    this.syncIngredientReferences()
  }

  syncIngredientReferences() {
    const ingredients = new Map(this.ingredientNameTargets.map((select, index) => {
      const name = select.value.trim()
      return [select.dataset.recipeFormKey, {
        name: name || `Ingredient ${index + 1} (enter a name)`,
        disabled: name.length === 0
      }]
    }))

    this.ingredientReferenceTargets.forEach((select) => {
      Array.from(select.options).forEach((option) => {
        const ingredient = ingredients.get(option.value)
        if (!ingredient) return

        option.text = ingredient.name
        option.disabled = ingredient.disabled
      })

      this.refreshAutocomplete(select)
    })
  }

  refreshAutocomplete(select) {
    if (!select.slim) return

    select.slim.setData(Array.from(select.options).map((option) => ({
      text: option.text,
      value: option.value,
      selected: option.selected,
      disabled: option.disabled
    })))
  }
}
