---
module: delivery-vertical-slice
tier: universal
summary: The vertical slice (one shippable feature, top-to-bottom through the layers) is the unit of delivery and maps to exactly one PR.
requires: [git-semilinear]   # "one slice = one PR" rests on the PR/merge model
---

# Vertical Slice Delivery

The unit of delivery is the **vertical slice**: one shippable feature cut top-to-bottom
through every layer it touches (API → Manager → Engine → Access → supporting utilities).

- One vertical slice = one shippable feature = one pull request.
- Scope and sequence work as slices, not as horizontal layers — a slice is independently
  shippable, reviewable, and revertable on its own.
- A slice's PR carries everything the feature needs to ship: implementation, tests at
  each layer, and any documentation updates.
