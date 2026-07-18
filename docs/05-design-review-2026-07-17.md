# Fond — Design Review & Redesign Brief (2026-07-17)

> Captured so the next session starts cold. Companion to `STATE_OF_PROJECT.md` (engineering audit) and `ROADMAP.md` (path to live). Design taste lives in memory `[[Mit design taste]]`.
> **Decision:** the next session runs a **full product rethink (redesign scope #3)** — revisit interaction model + information architecture + aesthetic, not just a visual skin. Brainstorm-first.
> **OUTCOME (updated 2026-07-18):** **"Two Faces" keepsake-card** structure is locked; the **Ember Folio** visual system and mockups are approved in `docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md`; the implementation plan is ready at `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md`. No redesign implementation has started.

---

## How the review was done (and its limit)

- **Seen live on the iOS 27 simulator:** the SignIn screen only.
- **Read from code, not rendered:** the Breathing Hub (`ConnectedView`, `ConnectedPartnerCard`, `ContextualCardView`, `ConnectedMessageInput`) + `docs/02-design-direction.md`.
- **Hard limit:** the app is auth-gated — the connected Hub (90% of usage) can't be reached at runtime without a real account **and** a paired partner. Hub findings below are **inferred from SwiftUI** (opacity values, layering, layout math), not observed pixels. **Next session: confirm visually** — sign in + pair on a device, or build a throwaway preview harness with mock data.

## The bar (four lenses)

1. **Good design craft:** hierarchy via weight/color/contrast (not size); constrained type + spacing scales; generous but *grouped* whitespace; one focal point; purposeful, interruptible motion. Generic tells = low contrast, centered-everything, even-but-ungrouped spacing, borders boxing everything, one flat accent, undesigned empty states.
2. **Apple / Liquid Glass (iOS 26→27):** SF + Dynamic Type + SF Symbols; 44pt targets; safe areas. **Liquid Glass belongs to the floating *control* layer only — never on content/cards/media; one glass layer, never stacked; text on glass needs a stabilized opaque plate ≥4.5:1**, and must hold across the iOS 27 user glass-clarity slider. Honor Reduce Transparency/Motion/Contrast.
3. **Mit's taste (`[[Mit design taste]]`):** restraint as luxury; warm-against-cool with ONE dominant warm accent, never washed-out, never pure black; **editorial serif type with real personality**; one signature gesture; spring-physics motion (`cubic-bezier(0.22,1,0.36,1)`); truth over theater. **Anti-references: glassmorphism cards + gradients, bento grids of identical rounded rectangles, templated/AI-looking UI.**
4. **Fond's own brief (`docs/02-design-direction.md`):** "Warm glass, not candy"; widget-is-the-product; content-over-chrome; warmth-through-restraint. (The brief is well-aligned with 1–3; the execution is where it drifts.)

## Verdict

**Vision is right; execution drifts into low-contrast, templated-glass territory — precisely the failure mode Mit's own anti-references name.** Fixable without changing the concept — it's a discipline problem, not a direction problem. (But Mit chose scope #3, so next session is free to question the concept/IA too, not just re-skin.)

## Findings

**SignIn (seen live):** washed-out mesh gradient with no focal warmth (reads like a default AI gradient); "Fond" is plain SF Bold with zero brand personality; accidental center void + on-the-nose floating heart; Google glass button nearly invisible on the pale gradient.

**Breathing Hub (inferred from code):**
- **Liquid Glass misused — the #1 problem:** the hero `ConnectedPartnerCard` uses `.fondCard()` = **`Glass.clear` on a CONTENT card**, over the **animated** mesh gradient, with a **status-color `EllipticalGradient` overlay** on top, then text — 3–4 translucent layers under the most important text, using the *Clear* variant (no legibility protection), no stabilized plate. Legibility risk on busy wallpaper / frosted end of the iOS 27 slider.
- **Low-contrast haze everywhere:** opacities `0.05 / 0.08 / 0.15 / 0.18 / 0.45` (card atmosphere, message bubble, card fills/borders, subtitle text, toolbar wordmark). The whole screen whispers; nothing anchors the eye. Opposite of "premium = strong hierarchy + contrast."
- **Flat hierarchy / no grouping:** partner card is one `VStack(spacing:10)` of 7 centered elements, uniform spacing, no proximity grouping; emoji (52pt) and name (~28pt) compete for focal point. "Centered everything" + "even-but-ungrouped" = generic tells.
- **Contextual cards = the anti-reference:** faint tinted rounded rectangles (`0.05` fill, `0.08` hairline border) → "bento grid of identical rounded rectangles" + borders-everywhere.
- **What's genuinely good (keep):** glass used *correctly* on toolbar icons + send button (control layer, tint = the one primary action); cooldown ring; breathing scale; nudge long-press w/ shake-on-cooldown; ambient status-color concept; negative tracking on the name; `monospacedDigit` for data; solid accessibility (labels, actions, `reduceMotion` guards). The *ideas* are strong; they're delivered too quietly and on glass they shouldn't sit on.

**System-wide:** semantic text styles used correctly (Dynamic Type works — keep) but all SF, no typographic personality (biggest gap vs Mit's taste — opportunity: a distinctive display face for 2–3 brand/hero moments, SF elsewhere). Palette is a sound warm-against-cool system on paper but applied at such low saturation/opacity the warmth never lands — push contrast, let amber truly dominate, demote lavender/rose to rare. Motion is on-brief and the most finished layer.

## What the next session should do (scope #3 — product rethink)

1. **Brainstorm first** (`superpowers:brainstorming`) — question the core interaction model + IA, not just visuals: is single-hub + widget-first the right frame? What is the ONE thing Fond does? Where's the single signature gesture?
2. Ground every choice in the four lenses above + `[[Mit design taste]]`.
3. Resolve the central tension: keep Apple-native Liquid Glass done *correctly* (controls only, content opaque/legible) vs. Mit's editorial-serif, high-contrast, less-glass sensibility. Likely synthesis: opaque high-contrast content + one distinctive display face + glass only on floating controls + one signature motion.
4. Confirm the real Hub visually before/while redesigning (sign-in + pairing, or a mock-data preview harness).
5. **Completed 2026-07-18:** visual spec approved and implementation plan written. Next: execute the plan in an isolated implementation session, then require simulator captures and Mit's visual sign-off before merge.

## References
- Engineering state: `STATE_OF_PROJECT.md` · Path to live: `ROADMAP.md` · Design intent: `docs/02-design-direction.md`
- Memory: `[[Mit design taste]]`, `[[Fond project status]]`
- Apple: HIG + Liquid Glass (WWDC25 "Meet Liquid Glass" #219, "Get to know the new design system" #356); Widgets HIG; watchOS HIG. Refactoring UI for craft fundamentals.
