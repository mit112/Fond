# Fond Visual System — Ember Folio

> **Date:** 2026-07-18
>
> **Status:** Implemented through Tasks 1–9 on 2026-07-18; awaiting Mit's final simulator visual approval before merge
>
> **Depends on:** `2026-07-17-fond-redesign-design.md`
>
> **Scope:** Visual system, motion, moment styling, widgets, and platform adaptations. The locked structure, product behavior, crypto, and feature set do not change.
>
> **Implementation plan:** `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md`
>
> **Non-UI handoff:** `docs/superpowers/plans/2026-07-18-ember-folio-claude-non-ui-handoff.md`

## 1. Direction

**Ember Folio** treats Fond as a small, substantial keepsake rather than a translucent interface. The field is quiet and cool-neutral. The card is opaque and warm. A single amber family marks the physical edge, the active face, and the primary action. Fraunces gives names and ritual questions a human, editorial character; Newsreader gives shared words the cadence of a note; SF Pro carries controls and factual metadata.

The intentional risk is typographic: the partner name is unusually large, soft, and slightly wonky. It is allowed to feel authored. Everything around it remains disciplined.

No mesh gradients, glass content cards, decorative haze, bubble chat, or repeated rounded containers survive this direction.

## 2. Named tokens

### 2.1 Color tokens

Colors use appearance-specific values where equal perceived contrast requires them. `fondAmber` is one semantic accent and one hue family, not a second accent.

| Swift token | Dark | Light | Role |
|---|---:|---:|---|
| `fondField` | `#191715` | `#EEE7DC` | Quiet app field behind the card |
| `fondKeepsake` | `#24201C` | `#FFF9EE` | Opaque card face |
| `fondInk` | `#F7EFE3` | `#26211C` | Primary text and symbols |
| `fondInkSecondary` | `#BDB2A5` | `#665C52` | Metadata and inactive labels |
| `fondRule` | `#6F665D` at 42% | `#807367` at 34% | Dividers; never a box outline |
| `fondAmber` | `#D68A1F` | `#A85F00` | Edge, active marker, primary action |
| `fondControlPlate` | `#312B24` | `#FFF9EE` | Fully opaque plate behind control text |
| `fondControlFallback` | `#342F29` | `#FFF9EE` | Reduce Transparency replacement for glass |
| `fondSendForeground` | `#211B14` | `#FFF9EE` | Send symbol on amber |
| `fondShadow` | `#000000` at 38% | `#2A2119` at 16% | Card shadow only |

Do not add lavender or rose to the primary interface. The relationship between the two voices is encoded by alignment, labels, and rules, not by a second brand hue.

### 2.2 Contrast

Ratios are WCAG relative-luminance ratios for the exact pairs above.

| Pair | Dark | Light | Rule |
|---|---:|---:|---|
| Primary text / card | `14.18:1` | `15.22:1` | Passes all text sizes |
| Secondary text / card | `7.76:1` | `6.23:1` | Passes small metadata |
| Control text / opaque plate | `12.26:1` | `15.22:1` | Stable across glass clarity settings |
| Secondary control text / plate | `6.71:1` | `6.23:1` | Stable across glass clarity settings |
| Amber / card | `5.79:1` | `4.66:1` | Safe for `TODAY` and active labels |
| Send foreground / amber | `6.10:1` | `4.66:1` | Safe for the send symbol |

The card/field contrast is intentionally subtle; physical separation comes from the amber edge and shadow. No essential information depends on that surface contrast.

### 2.3 Status color budget

Status color may occupy no more than **0.15% of the card face**. It appears only in:

1. the 8 pt status dot beside the status word on Now;
2. the 10 pt status dot in the compose control;
3. the 6 pt dot on a status-change thread moment.

Status words remain `fondInkSecondary`. No emoji, colored text, tinted card atmosphere, or status-colored message edge appears.

| Status group | Dark | Contrast on dark card | Light | Contrast on light card |
|---|---:|---:|---:|---:|
| Available | `#63B77E` | `6.63:1` | `#267347` | `5.53:1` |
| Busy | `#D77A65` | `5.28:1` | `#A44337` | `5.83:1` |
| Away | `#A08AC7` | `5.36:1` | `#66539A` | `6.13:1` |
| Sleeping | `#7E95C7` | `5.40:1` | `#49618E` | `5.92:1` |

The adjacent status word is always present, so color is never the sole signal. Unknown raw statuses use `fondInkSecondary` at full opacity and the word returned by `displayInfo(forRawValue:)`.

The remaining 12 statuses reuse this restrained set instead of adding 12 more hues: available green = available/happy/calm/exercising; busy coral = busy/stressed/excited; away lavender = away/sad/working/driving; sleeping indigo = sleeping; brand amber = eating/thinking of you/miss you/loving you. The written status remains authoritative.

### 2.4 Type tokens

Bundle **Fraunces Variable** for display roles. Bundle **Newsreader Variable** for shared human-authored content. New York and SF Pro are fallbacks, not alternate art directions. Apply custom fonts through `Font.custom(_:size:relativeTo:)` so Dynamic Type remains active.

| Token | Face | Base size / leading | Weight | Tracking | Use |
|---|---|---:|---:|---:|---|
| `typePartnerName` | Fraunces, opsz 72, SOFT 35, WONK 1 | 58 / 54 pt | 550 | `-1.8 pt` | Partner name only |
| `typeQuestion` | Fraunces, opsz 48, SOFT 28, WONK 1 | 34 / 36 pt | 520 | `-0.8 pt` | Today question |
| `typeMomentQuestion` | Fraunces, opsz 28, SOFT 22 | 21 / 24 pt | 500 | `-0.25 pt` | Past answered questions |
| `typePullQuote` | Newsreader, opsz 30 | 25 / 31 pt | 400 | `-0.2 pt` | Latest message on Now |
| `typeVoice` | Newsreader, opsz 20 | 18 / 24 pt | 400 | `0` | Answers and message moments |
| `typeBody` | SF Pro Text | 17 / 23 pt | Regular | system | Explanatory and empty-state copy |
| `typeControl` | SF Pro Text | 17 / 20 pt | Semibold | system | Buttons and compose text |
| `typeMetadata` | SF Pro Text, tabular figures | 13 / 17 pt | Medium | `+0.1 pt` | Signals and timestamps |
| `typeEyebrow` | SF Pro Text | 12 / 15 pt | Semibold | `+1.35 pt` | `TODAY` and day labels; uppercase |

Rules:

- Fraunces appears only in the name, ritual question, and past-question title.
- Newsreader appears only where one partner's words are being represented.
- Controls and facts stay SF Pro.
- At accessibility sizes, the Now footer wraps into two lines, the spread stacks into two rows, and each face becomes vertically scrollable inside the unchanged card object. The toolbar and compose control remain pinned outside it.
- Bold Text maps Fraunces 550 → 625 and Newsreader 400 → 500. Never synthesize a stroke.

### 2.5 Spacing and geometry tokens

| Token | Value | Use |
|---|---:|---|
| `space1` | 4 pt | Dot/label micro-gap |
| `space2` | 8 pt | Tight inline grouping |
| `space3` | 12 pt | Metadata and compact rows |
| `space4` | 16 pt | Standard content spacing |
| `space5` | 24 pt | Section spacing |
| `space6` | 32 pt | Card inset; compact width uses 28 pt |
| `space7` | 48 pt | Separation between the three Now blocks |
| `space8` | 64 pt | Large-screen breathing room only |
| `cardFieldMargin` | 20 pt compact; 28 pt regular | Card-to-field margin |
| `cardCornerRadius` | 34 pt | Both card faces |
| `controlHeight` | 52 pt | Toolbar and compose |
| `minimumHitTarget` | 44 × 44 pt | Every control |
| `contentMaxWidth` | 640 pt | iPad keepsake width |

## 3. Liquid Glass control layer

### 3.1 Principle

The toolbar and compose bar are the only custom Liquid Glass surfaces. They sit as siblings above the opaque card. They never overlap another glass layer, and no card, timeline moment, question, or text well receives glass.

Use one `GlassEffectContainer` for the top toolbar and one for the bottom compose cluster. Each cluster is spatially separate and never nested.

### 3.2 Toolbar

- Material: `.regular.interactive()` in a capsule, never `.clear`.
- Height: 52 pt; horizontal field inset: 16 pt.
- Gear and thread/history actions: 44 pt hit regions, untinted regular glass.
- `Now · Together`: one fully opaque `fondControlPlate` capsule inside the glass container, 36 pt high. Active label uses `fondInk`; inactive uses `fondInkSecondary`; the centered dot uses `fondAmber`.
- The plate is not another material. It is an opaque legibility substrate and does not refract.

### 3.3 Compose and send

- Compose shell: `.regular.interactive()` capsule, 56 pt high.
- Status and text entry sit within one opaque `fondControlPlate` region. The status affordance keeps a 44 pt target even though its visible dot is 10 pt.
- Send: a sibling circle in the same `GlassEffectContainer`, `.regular.tint(fondAmber).interactive()`, 52 × 52 pt. It must not be overlaid on top of the compose glass.
- The 20 pt upward arrow uses `fondSendForeground` and a medium symbol weight.
- Disabled send keeps the opaque plate but removes amber tint; it uses `fondInkSecondary`. Do not solve disabled state with opacity below 70%.

### 3.4 Clarity and accessibility fallbacks

- Test the iOS 27 Liquid Glass appearance/clarity control at both endpoints and default. Text contrast is measured against the opaque plate, never against sampled glass.
- The field behind glass remains flat `fondField`; no image, gradient, status tint, or scrolling timeline passes beneath the control cluster.
- **Reduce Transparency:** replace glass with `fondControlFallback`, a 1 pt `fondRule` stroke, and the same shadow footprint. Keep the text plates.
- **Increase Contrast:** use primary ink for inactive labels, increase the plate border to 1.5 pt, and increase the amber card edge to 2 pt. Do not change font size or introduce pure black/white.
- **Differentiate Without Color:** underline the active face label with a 2 pt, 12 pt-wide mark in addition to amber.

## 4. The keepsake card object

- Opaque fill: `fondKeepsake`. No material, blur, gradient, or image.
- Radius: 34 pt on compact devices. On iPad, cap at 38 pt rather than scaling proportionally.
- Edge: 1.25 pt `strokeBorder(fondAmber)`. Add a second inset highlight of `fondInk` at 6% opacity, 0.5 pt. This is a burnished edge, not a gradient.
- Field margin: 20 pt horizontal on iPhone; 28 pt on iPad. Maintain at least 12 pt between the card and either floating control.
- Dark shadow: y 18, blur 46, spread 0, `fondShadow` 38%.
- Light shadow: y 16, blur 38, spread 0, `fondShadow` 16%.
- Resting elevation is fixed. The card does not lift on scroll or tap.
- Breathing: scale `1.000 → 1.003 → 1.000`, 5.6 seconds, autoreversing, no opacity or shadow animation. Disable under Reduce Motion, Low Power Mode, or while the card is being dragged.

### Now composition

Use three vertical blocks:

1. Identity: status line, name, days/countdown.
2. Latest words: amber 2 pt leading rule, Newsreader pull quote, attribution/time.
3. Signals: one top rule and `distance · bpm · updated`, using tabular figures.

The name is leading-aligned. The quote sits near the optical vertical center, not the mathematical center. The footer is leading-aligned. Nudge remains the entire identity region's tap action, with a warm 120 ms edge pulse and one light haptic.

## 5. Card-turn motion

| Property | Value |
|---|---:|
| Perspective distance | 850 pt (`m34 = -1/850`) |
| Rest angles | 0° Now; 180° Together |
| Interactive range | 0°…180° plus 12° rubber-band overshoot |
| Drag mapping | `progress = clamp(abs(translationX) / (cardWidth × 0.88), 0…1)` |
| Face threshold | 42% progress, or predicted velocity over 450 pt/s |
| Spring mass | 1.0 |
| Spring stiffness | 330 |
| Spring damping | 32 |
| Initial velocity | gesture velocity / card width, clamped to ±3 |
| Typical settle | 420–480 ms |

Implementation behavior:

- Rotate around the vertical Y axis using the card's center anchor.
- Apply `.backfaceVisibility(.hidden)` to each independently rendered face. The Together face is pre-rotated 180°.
- At 90°, neither face may render mirrored content. VoiceOver focus changes to the destination face only after settle.
- A drag may start anywhere on the card except a 44 pt interactive answer/control target. Vertical intent wins when `abs(y) > abs(x) × 1.2`; otherwise the turn wins.
- Release settles to the nearest valid face using projected end translation. The spring is interruptible; a new drag inherits the current presentation angle.
- Fire one selection haptic when the turn commits past 90°, and no haptic on cancellation.

Discoverability:

- At rest, show a 7 pt amber edge peek on the side of the hidden face. Remove it after the user has completed five turns only if the toolbar labels remain visible.
- Indicator: active 7 pt amber dot, inactive 4 pt secondary dot, 5 pt gap. It sits in the field, never on the card.
- Toolbar labels are always tappable and use the same spring turn.

Reduce Motion:

- No perspective, rotation, breathing, or edge-parallax.
- Cross-fade current face out over 90 ms, swap at zero opacity, fade destination in over 120 ms. Total 210 ms using `.linear`; no scale.
- The indicator and toolbar label change at the swap point.

## 6. Together masthead and spread reveal

### Before both answer

- `TODAY` eyebrow, question, then one 48 pt opaque answer row with a 1 pt amber leading rule.
- The row says `Write your answer`; it is not glass and not a rounded card. Its 10 pt radius exists only to express a text-entry affordance.
- Partner state is one metadata line: `Maya hasn't answered yet.` No lock illustration or countdown.

### After both answer

- The question remains fixed.
- Two voices form a spread divided by a single vertical `fondRule`. At widths below 340 pt or accessibility sizes, stack them with a horizontal rule.
- Each side uses an SF eyebrow for the speaker and Newsreader for the answer. There are no quotation marks, portraits, bubbles, or tinted fills.
- Reveal: clip from the center gutter outward over 240 ms while each answer moves y 6 → 0 and opacity 0 → 1. The second voice trails by 70 ms. Use the `0.22, 1, 0.36, 1` timing curve. This is a quiet payoff, not another signature transition.
- Reduce Motion: simultaneous 120 ms opacity change only.

## 7. Thread of moments

The thread is a continuous document, not a stack of components.

### Day labels

`typeEyebrow`, `fondInkSecondary`, followed by a 1 pt rule that fills the remaining width. Use human labels: `Earlier today`, `Yesterday`, `Friday, July 17`. Never use numbered sections.

### Message

- Partner: leading aligned, 2 pt amber leading rule.
- You: trailing aligned, 2 pt `fondRule` trailing rule.
- Speaker/time in `typeMetadata`; copy in `typeVoice`.
- Maximum copy width: 78% compact, 62% regular. No fill, bubble, or corner radius.

### Nudge

- Centered on the timeline axis as `◉ Maya nudged you · 7:58`.
- Amber 16 pt concentric mark, secondary metadata text.
- On arrival, one 240 ms ring expansion from 0.8 → 1.1 → 1.0; Reduce Motion uses no animation.

### Status change

- Leading-aligned 6 pt status dot plus `Maya is sleeping · 11:04` in metadata.
- This is the only thread style allowed to reuse status color.
- Never show the old and new state as two colored chips.

### Answered question

- Question in `typeMomentQuestion`, followed by the same two-voice spread at a smaller scale.
- A single top rule separates it from the preceding moment. No card, disclosure chevron, or tinted background.
- If answers exceed the current view, show both in full when opened; do not truncate one partner more than the other.

## 8. Widget system — the ambient keepsake

The widget itself is the card. Never draw a card inside the widget and never add app-style glass controls.

### Rendering rules

- **Full color:** opaque `fondKeepsake`, 1 pt amber inset edge, partner name in Fraunces, shared words in Newsreader, facts in SF. Status color is dot-only.
- **Accented:** remove the authored background and edge. Assign the partner name and message to the primary group; mark only the status dot and a 1 pt voice rule with `widgetAccentable(true)`. Verify both user-selected tints and clear appearance.
- **Vibrant/accessory:** monochrome. Preserve hierarchy through size, weight, rule, and the status word. Do not simulate amber.
- **Reduced luminance / Always On:** remove shadow and halo, use primary text only, and omit message copy before reducing the name.

### Families

| Family | Composition |
|---|---|
| `accessoryInline` | `Maya · available · 6m`; no emoji |
| `accessoryCircular` | Fraunces `M` or first grapheme as hero; 6 pt status dot plus accessibility label; no timestamp inside the circle |
| `accessoryRectangular` | `Maya · available` on line one; one-line message on line two; status remains written |
| `systemSmall` | Dot/status, 30 pt name, two-line Newsreader message, updated time at bottom; leading aligned |
| `systemMedium` | Asymmetric 38/62 split: name/status left, message/signals right, divided by one amber rule |
| StandBy | Same medium split, name 40–44 pt, message capped at two lines, no small timestamps; distance or freshness may occupy the final line |
| watchOS Smart Stack | Name 22 pt, status/freshness above, one-line message below; no decorative background motion |

Widget relevance remains behaviorally unchanged. Visually, newly relevant partner updates may briefly brighten the amber rule for one timeline frame; no bounce or emoji animation.

## 9. Platform adaptations

### watchOS 27

- Smart Stack is the primary watch surface; use relevance cues already provided by the app.
- In the watch app, keep the card fill but let the physical screen supply the outer field. Use one face at a time; Digital Crown scrolls content, horizontal swipe turns faces.
- Nudge and heartbeat are 48 pt system glass buttons below the content, never over it. The tinted primary action uses amber; the second action is regular glass.
- Remove continuous breathing and all shadows for battery and Always On behavior.

### iPadOS 27

- Center a 560–640 pt card in the window; do not turn the two faces into side-by-side panes.
- Preserve the physical flip and cap name size at 68 pt.
- Place toolbar and compose at the same card-aligned width. Pointer hover raises control specular response only; the card itself does not hover.
- With keyboard attached: ⌘1 Now, ⌘2 Together, ⌘Return send.

### Mac widget continuity

- Fond has no native macOS or Catalyst app target. The iPhone widget can appear on Mac through widget continuity; no Mac view-layer adaptation is required.

## 10. Implementation mapping

### `FondColors`

Add or replace semantic values with:

- `field`, `keepsake`, `ink`, `inkSecondary`, `rule`, `amber`, `controlPlate`, `controlFallback`, `sendForeground`, `shadow`
- appearance-aware status values for available, busy, away, and sleeping groups

Keep compatibility aliases only during the implementation branch; remove the old surface/lavender/rose usages from the connected experience before merging.

### `FondTheme`

Create these focused modifiers/tokens:

- `fondField()` — flat field only
- `fondKeepsakeCard()` — opaque fill, edge, radius, shadow
- `fondFloatingToolbar()` — regular interactive glass container
- `fondComposeGlass()` — regular interactive glass container
- `fondControlPlate()` — opaque text substrate
- `fondSendGlass()` — tinted interactive glass sibling
- `fondReduceTransparencyControl()` — opaque fallback
- `FondType.partnerName`, `.question`, `.momentQuestion`, `.pullQuote`, `.voice`, `.body`, `.control`, `.metadata`, `.eyebrow`
- `FondSpacing` and `FondMotion.cardTurn`, `.quietReveal`, `.reduceMotionCrossfade`

Delete or prohibit `.fondCard()` for content. `.clear` glass has no use in the connected experience.

## 11. Acceptance checks

1. Exactly one opaque keepsake card is visible; no content uses Liquid Glass.
2. The partner name is the first focal point on Now in both appearances.
3. Amber is the only brand accent. Status hues occupy dots only.
4. Every text pair is at least 4.5:1 at 17 pt and below; meaningful graphic contrast is at least 3:1.
5. Toolbar and compose text remain legible at every iOS 27 Liquid Glass appearance/clarity setting.
6. Reduce Transparency removes blur without changing layout.
7. Reduce Motion replaces the turn with the specified cross-fade and removes breathing.
8. Dynamic Type through AX5 does not clip names, questions, answers, thread moments, or control labels.
9. The card turn is interruptible, finger-following, back-face-culled, and operable through labels as well as gesture.
10. Widget full-color, accented, vibrant, StandBy, reduced-luminance, and watch Smart Stack snapshots preserve the same hierarchy.

## 12. Source grounding

- Apple HIG, Materials: Liquid Glass is a distinct controls/navigation layer; do not use it in the content layer.
- Apple HIG, Accessibility: meet 4.5:1 for text up to 17 pt and 3:1 for larger or bold text; do not rely on color alone.
- Apple HIG, Typography: custom fonts must preserve Dynamic Type behavior.
- Apple WidgetKit: accented mode can replace the widget background and recolor primary/accent groups; full-color content must adapt conditionally.
- Apple watchOS: Smart Stack prominence is driven by relevance cues.
