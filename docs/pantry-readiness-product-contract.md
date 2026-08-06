# Pantry readiness product contract

Status: normative product and acceptance contract. Runtime implementation belongs to the follow-up pantry, allocation, and shopping-deficit tickets.

Hearth treats pantry readiness as household planning support, not medical advice. A queued meal is an active planned meal whose ingredient requirements still participate in readiness and allocation. Readiness explains what the household knows about preparing that meal; it never prevents someone from logging what they ate.

## Canonical readiness states

| Machine value | User-facing label | Meaning |
| --- | --- | --- |
| `needs_ingredient_check` | Needs ingredient check | At least one requirement or ingredient decision is unresolved. This state takes precedence even when another requirement has a known deficit. |
| `shopping_needed` | Shopping needed | Every requirement is resolved and at least one confirmed allocation deficit remains. |
| `ready_to_cook` | Ready to cook | Every requirement is resolved through allocation, a resolved substitution, or a not-needed decision, with no confirmed deficit. |

The primary state is determined in that order: unresolved first, then confirmed deficit, then ready. It is a planning projection rather than a guarantee that a meal can or should be prepared.

## Canonical ingredient decisions

| Machine value | User-facing label | Meaning |
| --- | --- | --- |
| `unknown` | Check ingredient | The default: the household has not resolved this planned-meal requirement. It produces no shopping work. |
| `on_hand` | On hand | The household explicitly confirmed pantry evidence that can be allocated to the requirement. |
| `missing` | Missing | The household explicitly confirmed that, at the time of the decision, this requirement has a deficit with no pantry evidence behind it. |
| `substituted` | Substituted | This planned-meal requirement points to a replacement; the replacement must itself be resolved before the meal can be ready. The recipe catalog is unchanged. |
| `not_needed` | Not needed | The household resolved this requirement for this planned meal without pantry allocation or shopping work. |

Ingredient decisions are plan-specific. They do not rewrite a recipe, silently apply to another meal, or constitute general clinical guidance.

A substitution never chains. The replacement of a substituted requirement resolves to `unknown`, `on_hand`, or `missing` only; it can never itself be substituted or marked not needed.

## Canonical pantry states

| Machine value | User-facing label | Meaning |
| --- | --- | --- |
| `confirmed` | Confirmed | The household asserted an exact positive amount in a recognized unit. This is the only state that carries an amount, and it is the only allocatable evidence. |
| `low` | Running low | The household knows the ingredient is short without measuring it. It carries no amount, is never allocatable, and leaves the requirement unresolved. |
| `out` | Out | The household asserted there is none. It carries no amount and semantically supplies zero, which resolves the requirement as a deficit. |
| `unknown` | Not tracked | The household has no current pantry evidence, either because it never tracked the ingredient or because it explicitly cleared prior evidence. It carries no amount and is never allocatable. |

A pantry state describes what the household knows about its shelves. It is a different vocabulary from the planned-meal `unknown` ingredient decision above: `unknown` pantry evidence is household-wide and says nothing was observed, while an `unknown` ingredient decision is plan-specific and says one meal's requirement is unresolved. Neither implies the other.

Not tracking an ingredient at all is equivalent to `unknown`; the household is never backfilled with `unknown` rows for its whole ingredient catalog.

## Planned-meal requirement snapshots

A planned meal carries a positive recipe scale. A scale of `1` means one full recipe yield, not one serving; consumed portions remain a logging concept. The scale multiplies each measurable requirement exactly and never rewrites the recipe's authored amount.

Each planned meal owns its requirements as snapshots rather than reading recipe lines live. A snapshot keeps the canonical ingredient, the authored name, amount, and unit exactly as written, the scaled required quantity when it is measurable, and the recipe provenance it came from. Readiness, allocation, and shopping consider active snapshots only.

Reconciliation runs whenever the plan's recipe, scale, or a referenced recipe line changes:

- a presentational recipe edit that does not change requirement identity, required quantity, or unit keeps the requirement and its decision;
- an obsolete requirement that was never resolved simply disappears;
- an obsolete requirement that the household already resolved becomes superseded provenance with a timestamp and a reason, is immutable from then on, and no longer participates in readiness;
- current requirements reappear as fresh `unknown` snapshots.

Supersession reasons are lifecycle bookkeeping — a recipe swap, a scale change, a changed requirement, or a removed source line. They are not readiness states or ingredient decisions and carry no household meaning of their own. Deleting a planned meal deletes its decision history with it.

## Pantry confirmation

Pantry confirmation is an explicit household assertion. It identifies the canonical ingredient, a pantry state, the time confirmed, provenance such as a pantry check or purchase confirmation, and the household person who confirmed it. Measurable knowledge is recorded as `confirmed` with an exact positive amount and a compatible recognized unit; knowledge that cannot be measured is recorded as `low`, `out`, or `unknown` rather than as a faithful display string. Every explicit observation refreshes the time, provenance, and confirming person. These are product concepts, not a database schema prescribed by this ticket.

Recipe presence, a prior generated shopping row, inferred stock, checking off a shopping item, and logging a meal are not pantry confirmation. Completing shopping work is checklist state only. A separate confirmation action adds the purchased amount to pantry evidence, after which allocation may change meal readiness.

Adjusting confirmed inventory is exact and signed. It applies only to a `confirmed` amount in a compatible recognized unit, stays `confirmed` while the result is positive, becomes `out` at exactly zero, and is rejected when it would take inventory below zero. `low`, `out`, and `unknown` are re-established through confirmation rather than adjusted. Hearth does not consume pantry evidence automatically.

## Allocation, dates, and priority

Confirmed compatible pantry evidence is allocated across active planned meals in ascending `planned_on` order, then by stable planned-meal identity. This makes the default deterministic: when two meals need the same limited ingredient, the earlier meal wins.

Allocation draws from household-level confirmed pantry evidence independently of any single requirement's decision. A requirement decided `missing` may still receive a partial allocation when compatible evidence is available, leaving only its shortfall as the confirmed deficit. Generated shopping work follows that remaining allocation deficit rather than the `missing` decision alone, so a requirement decided `on_hand` that loses its allocation to an earlier or explicitly prioritized meal also produces a generated deficit row.

The household may explicitly prioritize a planned meal ahead of that default. The override affects allocation order only; it does not change the meal date or recipe. Rescheduling or changing priority releases the old allocation and recomputes the affected demand once. The same pantry amount is never reserved twice. Removing an override restores date-plus-stable-identity ordering.

## Free-text and unitless requirements

A numeric unitless amount participates in allocation only when the measurement foundation classifies it as a compatible count. Hearth does not invent a count, density, or unit conversion.

An unparseable or incomparable amount such as salt “to taste” remains source-specific and faithful. While its decision is `unknown`, the meal is `needs_ingredient_check` and no generated shopping row exists. If the household explicitly marks it `missing`, it becomes a source-specific confirmed deficit row displaying “to taste.” It is not numerically allocated, merged with another source, coerced to zero, or discarded.

## Household and person visibility

A selected person's meal and readiness views include household-shared planned meals plus meals assigned to that person. They exclude plans assigned only to another person.

The shopping list is household operational data. It includes confirmed deficits from every household plan exactly once, including other people's plans, and does not duplicate a household-shared plan per person. A manual shopping item remains household checklist intent independent of generated deficits. It neither changes meal readiness nor confirms, reserves, or consumes pantry evidence.

## Logging is non-blocking

Meal logging remains available in `needs_ingredient_check`, `shopping_needed`, and `ready_to_cook`. A log records what happened; it does not retroactively resolve ingredient decisions, confirm pantry stock, or rewrite the planned meal's readiness history.

## Cold-turkey shopping cutover

The later shopping-deficit implementation must replace today's all-planned-ingredient generation with confirmed allocation deficits in one cold switch. It must not retain a feature flag, legacy generator, version suffix, compatibility projection, or dual meaning for generated rows.

On the first reconciliation after that switch:

- untouched, open legacy-generated rows disappear as stale;
- user-managed rows survive as household shopping intent, keeping their name, quantity, and household state but losing planned-meal provenance;
- completed rows survive as non-open tombstones, keeping their name, quantity, and completion state but losing planned-meal provenance;
- manual rows remain independent household intent;
- affected planned meals may return to `needs_ingredient_check`; and
- the open generated shopping list may temporarily become mostly or entirely empty while the household reviews unknown requirements.

A surviving legacy, user-managed, manual, or completed row does not imply pantry confirmation. The cutover does not backfill confirmation from shopping history.
Surviving user-managed and completed rows therefore render without meal attribution until a current requirement re-associates them.

## Runtime ownership and follow-up proof

Planned-meal requirement snapshots and their decisions are persisted runtime state. `PlannedMeal` reconciles them on commit — ahead of shopping reconciliation — for the web plan form, the Agent planned-meal mutations, and recipe authoring and import. Decision commands exist on the model and still await the ingredient review UI.

Pantry evidence is persisted as `PantryItem` with model-level confirmation and adjustment commands, but no user-reachable entry point creates or reads it yet.

Readiness derivation and allocation are implemented as `Household::PantryAllocation`, a derived projection with no persisted state: each engine recomputes reservations from the household's current pantry evidence, plan dates, priorities, substitutions, and decisions, so a change needs no invalidation and reading readiness never consumes stock or rewrites a decision. Its queue is `PlannedMeal.allocatable` — every household plan with no `Meal` rows, ordered by explicit priority, then date, then planned-meal id. `PlannedMeal#prioritize_before!` and `#clear_allocation_priority!` own the override. Nothing calls the engine yet.

Purchase confirmation and shopping deficits remain scaffold-only. Today `ShoppingList#reconcile!` is reached by `ShoppingListsController#show` and `PlannedMeal` after-commit callbacks, while Meals, Today, and MCP projections consume an existing list without reconciling it. The follow-up cold-switch ticket must consume `Household::PantryAllocation` deficits through those production seams and prove the actual user/runtime path. Releasing or consuming a reservation when a plan is skipped, deleted, rescheduled, or cooked belongs to the later lifecycle ticket; leaving the allocation queue on the first conversion is a query boundary here, not a consumption event. Until that ticket lands, a past plan that was never cooked keeps its place in the queue and holds its reservation.
