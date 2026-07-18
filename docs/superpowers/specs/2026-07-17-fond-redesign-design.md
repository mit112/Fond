# Fond — Product Redesign Spec: "Two Faces" (Keepsake Card)

> **Date:** 2026-07-17 · **Author:** brainstorm session (scope #3 — full product rethink)
> **Status:** **Structure / IA / interaction model = LOCKED.** Ember Folio visual system + mockups approved 2026-07-18. Implementation plan ready at `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md`; implementation has not started.
> **Companions:** design review `docs/05-design-review-2026-07-17.md` · engineering `STATE_OF_PROJECT.md` + `ROADMAP.md` · original brief `docs/02-design-direction.md` · taste memory `[[mit-design-taste]]` · superseded prior redesign `docs/superpowers/specs/2026-03-21-connected-view-redesign.md`
> **Scope note:** this is a **view-layer + information-architecture rework only.** Zero-knowledge crypto, the Firestore data model, Cloud Functions, App Group bus, and the full feature set are **unchanged**. History's *data* stays append-only + encrypted; only its *UI* moves (it becomes the Together thread).

---

## 1. Why (the problem we're fixing)

The prior "Breathing Hub" (`ConnectedView`) was confirmed — from source **and** real iOS 27 renders (light + dark, iPhone 17 Pro) — to drift into exactly the failure modes Mit's taste names as anti-references:

- **The emoji is the hero, not the person.** A 52pt full-color status emoji is the highest-contrast object on screen; it out-shouts the name in both appearances. Contradicts the brief's own "the name is the anchor."
- **The brand accent can't win, by construction.** The hero's color *is* the status color (green/etc.), so "ONE dominant warm accent" is structurally impossible — the dominant hue changes with status and is usually not amber.
- **Card-in-void + low-contrast haze.** `.fondCard()` = `Glass.clear` on a *content* card over an animated gradient, opacities `0.05–0.45` everywhere; the message reads like a disabled text field; "FOND" and "hold to nudge" are ghosts.
- **Flat, ungrouped, centered stack.** 8 centered elements in one uniform `VStack(spacing: 10)`; no proximity grouping; contextual cards are the "faint tinted rounded rectangles" anti-reference.
- **Dark ≫ light** — dark ("warm charcoal") is markedly better; light is a pale wash.

**Root cause (conceptual, not cosmetic):** the app tried to *be the widget at 10× size.* If the widget is already the ambient surface (the brief's own claim), a whole app screen of "ambient" has nothing to do but whisper. That's why scope #3 reworked the concept, not just the skin.

---

## 2. The ONE thing Fond does

**Let two people feel each other's presence through the day *and* share one small daily ritual — presence without pressure.**

**Confirmed product intent:** serve **BOTH** the ambient glance **and** the daily-ritual depth, **evenly** — do *not* shrink the app behind the widget, and do *not* abandon ambient presence. (This was a deliberate user choice over "ambient glance only" and "daily ritual only.")

The hard part of "both, evenly": the old screen failed at it because **one flat plane tried to do both jobs at once**, so ambient won and then whispered. The fix is to give glance and depth **distinct altitudes** — two faces of one object — so neither starves.

---

## 3. The bar — four lenses (from the design review, unchanged)

1. **Good-design craft** — hierarchy via weight/color/contrast; constrained type + spacing scales; grouped whitespace; **one focal point per moment**; purposeful, interruptible motion. Generic tells to avoid: low contrast, centered-everything, even-but-ungrouped spacing, borders boxing everything, one flat accent, undesigned empty states.
2. **Apple / Liquid Glass (iOS 26→27)** — SF + Dynamic Type + SF Symbols; 44pt targets; safe areas. **Glass belongs to the floating *control* layer only — never on content/cards/media; one glass layer, never stacked; text on glass needs a stabilized opaque plate ≥4.5:1; must hold across the iOS 27 glass-clarity slider.** Honor Reduce Transparency / Motion / Contrast.
3. **Mit's taste** (`[[mit-design-taste]]`) — restraint as luxury; warm-against-cool with **ONE dominant warm accent** (amber), never washed-out, never pure black; **editorial serif with real personality**; **one signature gesture, everything else quiet**; spring-physics motion (`cubic-bezier(0.22,1,0.36,1)`); truth over theater. **Anti: glassmorphism cards + gradients, bento grids, templated/AI-looking UI.**
4. **Fond's own brief** — "warm glass, not candy"; the widget is the product; content over chrome; warmth through restraint.

---

## 4. Product frame — DECIDED

**Metaphor: Fond is one warm keepsake card — a locket you flip.**

This single metaphor fixes the original sin. The old card floated in a void because it was translucent glass with nothing to *be*. Now the card is **the object**: opaque, substantial, warm, amber-edged, sitting in a quiet field. It has two sides. **Glass never touches content** — it lives only on the floating toolbar + compose bar that *hover over* the card as its persistent frame.

---

## 5. Interaction model — DECIDED ("Two Faces")

One app, one *object*, two faces. A persistent glass toolbar (top) and compose bar (bottom) frame both faces, so it always reads as **one app showing two facets**, not two screens.

- **Face "Now" (Presence)** — your person, right now. The emotional hero. (See §6.)
- **Face "Together"** — the shared day: today's ritual question + the living thread of moments. **Absorbs the old History sheet.** (See §7.)

### 5.1 Signature gesture = the **card turn**
- The card physically **turns on its vertical (Y) axis** to reveal the other face — two sides of one object, literal to "flip the card."
- **Interactive / finger-following** (the turn tracks the drag, rubber-bands, then springs to the nearest face on release — "the camera is a spring, not a tween"). **Back-face culled** so you never see mirrored text.
- **Reduce Motion → cross-fade** (no rotation).
- **This is where the single unit of boldness is spent** (Mit's explicit choice: bold *motion*, quiet everything else). Do not add a second showy transition elsewhere.

### 5.2 Discoverability (kills the "half is hidden" risk)
- A **page-edge peek** of the far face + a **two-dot indicator** + tappable **`Now · Together`** labels in the toolbar. The turn is *discovered*, never required to reach core content.

### 5.3 Other model decisions
- **Nudge = tap your person on the Now face** (warm ripple + haptic; gentle resistance on cooldown). Explicit and legible — **not** a hidden long-press. One signature gesture, not two competing ones.
- **Settings** = the gear (toolbar). **Days-together / countdown** = a quiet line under the name on Now (emotionally important for the LDR lean).
- **Compose bar is shared across both faces** and is always the same one thing: `● status · say something · ↑`. Answering the daily question is its *own* affordance inside the Together masthead, so compose never overloads.

---

## 6. Face "Now" (Presence) — spec

The craft problem: a full card-face that glances well but **does not whisper**. Solved by **contrast + one focal point + grouping**.

- **The name is the hero** — set huge in an **editorial serif** (display size, tight leading, negative tracking), full contrast. It wins the focal fight outright.
- **Status is a signal, not the hero** — a small colored dot + word (`● available`) above the name. Amber owns the card edge + chrome; status color lives *only* in that dot. Emoji demoted to a small inline glyph (or dropped).
- **Her words are an editorial pull-quote** — the message set larger than metadata with real breathing room, so it reads like *a note in her hand*. No gray bubble.
- **Presence signals = one grouped footer row** — `1,284 mi · 72 bpm · 6m ago`, tight, monospaced digits.
- **Three groups, intentional spacing** — (a) identity: dot · **name** · day/countdown line; (b) her words; (c) signals footer. Generous space *between* groups, tight *within*. (The single biggest fix vs. the old flat stack.)
- **Motion:** card breathes (1.0→1.005), bpm pulses — both off under Reduce Motion.
- **Stale/empty with dignity:** a quiet "last seen," never a void or a scary warning.

```
+-------------------------+   <- glass toolbar (floats)
|  gear      Now·Together  hist
|                         |
|   +-----------------+   |   <- THE CARD (opaque,
|   |                 |   |      warm, amber edge,
|   |  ● available    |   |      soft shadow)
|   |                 |   |
|   |  Sarah          |   |   <- serif hero
|   |  day 412        |   |
|   |                 |   |
|   |  "made coffee,  |   |   <- her words,
|   |   thinking      |   |      pull-quote
|   |   about our     |   |
|   |   trip"         |   |
|   |                 |   |
|   |  1,284mi·72·6m  |   |   <- grouped footer
|   +-----------------+   |
|                         |
|  (● status)  say..   ^  |   <- glass compose (floats)
+-------------------------+
       *  o   (turn to Together)
```

---

## 7. Face "Together" (the back of the card) — spec

A **ritual masthead** (why you come back) over a **thread of moments** (what you've built).

- **`TODAY` masthead — the ritual, given primacy.** The daily question as an editorial line. Before you've both answered: your answer field + a quiet `Sarah hasn't answered yet`. Once both have: the two answers reveal as a **spread** — one question, two voices, like a page in a shared book. That reveal is the daily payoff.
- **The thread absorbs History and becomes "moments."** Not a chat log — a *restrained, warm timeline* of the meaningful things between you: messages, nudges, status changes (`Sarah → sleeping`), past answered questions. Grouped by day with quiet labels.
- **Your words vs. hers by alignment + a thin edge** (amber / lavender), never heavy filled bubbles — editorial and sparse, so it never tips into "a chat app."
- **Compose** = the same shared bar. **Empty state with dignity:** a brand-new couple sees the question standing alone — `Answer today's question to start your story` — not a blank thread.

```
+-------------------------+   glass toolbar
|  gear    Now·Together    hist
|                         |
|  TODAY                  |   masthead = ritual
|  "What's one small      |
|   thing you're looking  |
|   forward to?"          |
|   [ tap to answer ]     |   before both answer
|   -- or --              |
|   you    the trip       |   after: the spread
|   Sarah  seeing you     |
| ----------------------- |
|  earlier today          |   thread of moments
|   Sarah -> sleeping     |
|   you    miss you       |
|   ·  Sarah nudged you   |
|                         |
|  yesterday              |
|   you both answered ->  |
|                         |
|  (● status) say..    ^  |   glass compose
+-------------------------+
     o  *   (turn to Now)
```

---

## 8. RESOLVED — Ember Folio visual system

The complete approved system is `docs/superpowers/specs/2026-07-18-fond-ember-folio-visual-system-design.md`. It locks Fraunces + Newsreader + SF Pro typography, appearance-aware Ember Folio colors, control-layer-only Liquid Glass, the opaque card object, card-turn physics, Together spread/thread treatments, widget families, platform adaptations, and five high-fidelity app mockups.

The original handoff checklist is retained below as traceability; every item is resolved by that companion spec.

Everything above is the **skeleton**. The **visual system + high-fidelity craft** is the next layer, to be developed in claude design and brought back:

1. **Typography** — the editorial serif for hero moments. Candidate: **Fraunces** (Mit's portfolio display face, variable, optical sizing); native alternative: **New York**. Body face (SF vs. Newsreader). Full type scale, tracking, leading.
2. **Palette** — exact **warm-charcoal** (dark) + **warm-ivory** (light); the single **amber**; how much **status color** survives and precisely where (proposed: dot only + hairline); authored **high-contrast in both** light and dark (dark-first).
3. **Liquid Glass specs** — toolbar / compose / send treatments (`.regular` / `.clear` / `.tint(amber)` / `.interactive()`); stabilized plate ≥4.5:1 for any text on a control; robustness across the iOS 27 clarity slider; Reduce-Transparency fallbacks.
4. **The card object** — elevation/shadow, amber edge treatment, corner radius, field/margin around it, breathing amplitude.
5. **The card-turn motion spec** — perspective, max angle, spring constants, finger-tracking curve, edge-peek, dot indicator, Reduce-Motion cross-fade.
6. **The reveal "spread"** treatment; the **thread moment** styles (message / nudge / status-change / answered-question); day labels.
7. **High-fidelity mockups** — Now + Together, **light + dark**, plus the flip mid-turn.
8. **Widget rethink** — the ambient half is arguably the *primary* surface; it must be reconsidered **alongside** the app (not left as-is), so app and widget read as one design language. Then **watchOS** and **macOS / iPadOS** adaptations.
9. **Feature set** — keep all: status (16 in 4 categories), 100-char message, nudge, heartbeat, distance, daily prompt, countdown, days-together, history-as-thread. Crypto + data model **unchanged**.

---

## 9. Implementation handoff

Execute `docs/superpowers/plans/2026-07-18-ember-folio-implementation.md` task-by-task. Respect the existing architecture: the redesign is a rework of `ConnectedView` + its child views (`ConnectedPartnerCard`, `ContextualCardView`, `ConnectedMessageInput`, `HistoryView`, `StatusPickerSheet`, `DailyPromptCard`), `FondTheme`, `FondColors`, widgets, and the watch presentation; the App Group bus, NSE, Cloud Functions, Firestore schema, and crypto do **not** change.
