# Fond — Design Direction & Visual Language

> Reference document for all UI/UX decisions across app, widgets, and watchOS.
> Created: February 24, 2026

---

## Design Philosophy

**"Warm glass, not candy."**

Fond should feel like a beautifully crafted piece of jewelry — premium, intimate, gender-neutral. Not a sticker sheet, not a toy. The app exists to make one person feel closer to another. Every pixel should serve that feeling.

**Three guiding principles:**

1. **The widget IS the product.** The in-app experience serves the widget, not the other way around. Most users interact with Fond by glancing at their lock screen, not opening the app.
2. **Content over chrome.** Your partner's name, status, and message should dominate. Everything else is secondary.
3. **Warmth through restraint.** Romantic doesn't mean pink. Inviting doesn't mean cluttered. The emotional warmth comes from color, motion, and typography — not from illustration or ornamentation.

---

## Color System

### Core Palette

| Role | Token | Light Mode | Dark Mode | Usage |
|---|---|---|---|---|
| **Background** | `fondBackground` | `#FAF8F5` (warm cream) | `#1A1A1E` (warm charcoal) | App background, sheets |
| **Surface** | `fondSurface` | `#FFFFFF` | `#2A2A2E` | Cards, elevated containers |
| **Primary Accent** | `fondAmber` | `#E8A838` | `#F0B84A` | CTAs, active states, brand moments |
| **Secondary Accent** | `fondLavender` | `#B8A0D2` | `#C4B0DE` | Subtle highlights, secondary info |
| **Tertiary** | `fondRose` | `#D4A0A0` | `#DEB0B0` | Sparingly — reactions, special moments |
| **Text Primary** | `fondText` | `#1A1A1E` | `#F5F3F0` | Headlines, partner name |
| **Text Secondary** | `fondTextSecondary` | `#6B6B70` | `#A0A0A5` | Timestamps, labels |
| **Glass Tint** | — | `.amber.opacity(0.15)` | `.amber.opacity(0.2)` | Liquid Glass surfaces |

### Status Colors

| Status | Emoji | Color Accent | Rationale |
|---|---|---|---|
| Available | 💚 | Soft green | Universal "online" signal |
| Busy | 🔴 | Muted coral | Attention without alarm |
| Away | 🌙 | Soft lavender | Calm, transitional |
| Sleeping | 😴 | Deep indigo | Restful, dark |

### What We Avoid
- Full-saturation pink as a primary color (gendered, childish)
- Pure black backgrounds (cold, harsh — use warm charcoal)
- Neon or electric colors (gaming aesthetic, not intimate)
- More than 2 accent colors on any single screen

---

## Typography

Use the system San Francisco font with intentional weight hierarchy to create warmth through scale contrast:

| Element | Style | Weight | Size |
|---|---|---|---|
| Partner name (hero) | `.largeTitle` | Bold | 34pt |
| Status text | `.title2` | Medium | 22pt |
| Message text | `.title3` | Regular | 20pt |
| Timestamp / "ago" | `.caption` | Regular | 12pt |
| Section labels | `.subheadline` | Semibold (uppercase, tracked) | 15pt |
| Button labels | `.body` | Semibold | 17pt |

**Key rule:** The partner's name is always the largest text on screen. It's the emotional anchor.

---

## Animation & Motion

### Philosophy
Motion in Fond serves **emotional feedback**, not decoration. Every animation should make the user feel that their connection is alive and responsive. Stale, static UI feels like a dead app. Fluid motion feels like your person is right there.

### 1. Animated Mesh Gradient Background

The connected state uses a slowly animating `MeshGradient` as a living background — warm amber/gold/lavender tones shifting slowly. This creates a "breathing" feeling, like the connection itself is alive.

```
MeshGradient (3×3 grid)
  Colors: warm amber, soft gold, muted lavender, cream
  Animation: easeInOut, 6s duration, repeating, autoreverses
  Animates: center point position + 2 color shifts
  Intensity: SUBTLE — positions shift by ~0.15, not dramatic
```

**Where it appears:**
- Connected view background (behind the partner card)
- Pairing success moment (briefly intensifies)
- Sign-in / onboarding backgrounds

**Where it does NOT appear:**
- Widgets (too battery-intensive)
- Settings screens (keep utilitarian)

### 2. Liquid Glass Interactions (iOS 26)

All floating controls use Liquid Glass with warm amber tint:

- **Send button**: `.buttonStyle(.glassProminent)` with `.glassEffect(.regular.tint(fondAmber))` — the most prominent interactive element
- **Status picker**: `GlassEffectContainer` — status options morph into/out of existence using `.glassEffectTransition(.materialize)`
- **Toolbar items**: `.glassEffect()` default — back button, settings gear, history
- **Sheets**: Let system Liquid Glass handle partial-height sheets naturally (remove any custom `presentationBackground`)
- **Tab bar**: None — app is single-screen hub, no tabs needed

### 3. SF Symbol Effects

Leverage built-in symbol animations for alive-feeling UI:

| Trigger | Symbol | Effect | Duration |
|---|---|---|---|
| Status received from partner | Status emoji | `.symbolEffect(.bounce)` | Once |
| Message received | `envelope.fill` | `.symbolEffect(.bounce.up)` | Once |
| Sending message | `arrow.up.circle.fill` | `.symbolEffect(.pulse)` | While sending |
| Connected / paired | `heart.fill` | `.symbolEffect(.breathe)` | Continuous, subtle |
| Send success | `checkmark.circle.fill` | `.contentTransition(.symbolEffect(.replace))` | Replaces send icon briefly |
| Error state | `exclamationmark.triangle` | `.symbolEffect(.wiggle)` | Once |

### 4. State Transitions

| Transition | Animation | Details |
|---|---|---|
| Partner data arrives | Spring | New name/status/message slides in with `.spring(response: 0.5, dampingFraction: 0.8)` |
| Status change | Content transition | `.contentTransition(.numericText())` for the status label; emoji does `.symbolEffect(.bounce)` |
| History sheet appears | Morphing sheet | System iOS 26 sheet morph from the partner card (via `navigationTransition(.zoom)` or `.matchedTransitionSource`) |
| Pairing success | Celebration | Mesh gradient intensifies for 1s + `heart.fill` does `.symbolEffect(.bounce.up.byLayer)` + haptic `.success` |
| Unlink / disconnect | Fade + scale down | Partner card fades to 0 and scales to 0.9 over 0.4s, then view transitions to unpaired state |
| Pull to refresh | Rotation | Custom refresh indicator — heart icon rotates, not the default spinner |

### 5. Haptic Feedback

| Event | Haptic | Rationale |
|---|---|---|
| Message sent | `.impact(.medium)` | Confirms action |
| Status changed | `.impact(.light)` | Lighter than message |
| Partner update received | `.notification(.generic)` | Subtle "ping" |
| Pairing success | `.notification(.success)` | Celebratory |
| Unlink confirmed | `.notification(.warning)` | Serious action |
| Rate limit hit | `.notification(.error)` | Blocked action |

### 6. Micro-Interactions

- **Rate limit countdown**: Circular progress ring around the send button that fills as the cooldown expires — not a text timer.
- **Message input**: Text field expands smoothly with spring animation as user types multiline. Character count fades in near the limit.
- **Pairing code entry**: Each character slot fills with a subtle scale-up + haptic as the user types. When all 6 are entered, auto-submit with no button needed.
- **"Last updated" timestamp**: Fades between time values with `.contentTransition(.numericText())` as time passes.
- **Partner card "breathing"**: Very subtle scale oscillation (1.0 → 1.005 → 1.0) on the partner card, synchronized with the mesh gradient. Just enough to feel alive.

---

## App Structure (Widget-First)

### Screen Architecture

```
┌─────────────────────────────────────┐
│  Sign In (Apple / Google buttons)   │  ← Only shown once
│  → Display Name Entry               │  ← Only shown once
│  → Pairing (Generate / Enter Code)  │  ← Only shown once
└────────────┬────────────────────────┘
             │
             ▼
┌─────────────────────────────────────┐
│                                     │
│       CONNECTED VIEW (Hub)          │  ← 90% of app usage
│                                     │
│  ┌─────────────────────────────┐    │
│  │    Animated mesh gradient    │    │  Background
│  │         background           │    │
│  │  ┌───────────────────────┐  │    │
│  │  │    Partner Card       │  │    │  Hero element
│  │  │  Name (large title)   │  │    │
│  │  │  💚 Available         │  │    │
│  │  │  "miss you already"   │  │    │
│  │  │  2 min ago            │  │    │
│  │  └───────────────────────┘  │    │
│  │                              │    │
│  │  ┌─ Status Picker ────────┐ │    │  Glass pills
│  │  │ 💚  🔴  🌙  😴        │ │    │
│  │  └────────────────────────┘ │    │
│  │                              │    │
│  │  ┌─ Message Input ────────┐ │    │  Glass surface
│  │  │ Type a message...  [→] │ │    │
│  │  └────────────────────────┘ │    │
│  └──────────────────────────────┘    │
│                                     │
│  [⚙️ Settings]          [📜 History]│  ← Glass toolbar items
└─────────────────────────────────────┘
```

### Connected View (The Hub)

This is the entire app for most users. One screen. No tab bar. No navigation stack. Everything is here or accessible via sheets:

- **Partner card**: Dominant, center-screen. Shows partner name (largest text), status emoji + label, last message, timestamp. Subtle glass surface behind it, or transparent with the mesh gradient showing through.
- **Status picker**: Row of glass-tinted pills below the partner card. Tap to change your own status. Selected status has `.glassProminent` treatment.
- **Message input**: Glass surface at the bottom. Text field + send button. Send button uses `.glassProminent` with amber tint.
- **Toolbar**: Floating glass toolbar. Settings gear (left), History scroll (right). These slide up sheets.

### History Sheet

Slides up from the partner card using iOS 26 morphing sheet presentation:

- Chat-bubble style layout (your messages right, partner's left)
- Warm backgrounds on bubbles (not blue/gray — use amber tint for yours, lavender tint for partner's)
- Timestamps grouped by day
- Scrolls from bottom (newest at bottom, like Messages)

### Settings Sheet

Minimal. Glass-styled list:

- Display name (editable)
- Connection info (partner name, connected since)
- Disconnect button (red, requires confirmation)
- Sign out

### Onboarding Flow

1. **Welcome** — App name + tagline on animated mesh gradient. "Your Person, At a Glance." Single CTA: "Get Started"
2. **Sign In** — Apple + Google buttons on glass surface. Clean, no clutter.
3. **Display Name** — "What should your partner see?" Single text field. Glass surface.
4. **Pairing** — Two-tab glass segmented control: "Create Code" / "Enter Code". Code display is large, mono-spaced, with copy button. Code entry has individual character slots with auto-advance.
5. **Success** — Mesh gradient celebration moment. "You're connected with [Name] 💛". CTA: "Add Widget to Home Screen" (with visual tutorial).
6. **Widget Tutorial** — Shows how to add the Fond widget. This is critical — if they skip this, they miss the product.

---

## Widget Design

### Visual Style

- Full Liquid Glass adoption via `widgetRenderingMode` on iOS 26
- In `.accented` mode: warm amber tint
- In `.vibrant` mode (lock screen): white on translucent
- Status emoji is the visual anchor — always the largest element in every widget size
- Partner name in semibold, status in regular weight, message in secondary color

### Per-Family Layout

**accessoryInline**: `"Alex is available 💚"` — text only, system handles styling

**accessoryCircular**: Status emoji centered (large), time-ago below (tiny). Not-connected state: heart.slash icon.

**accessoryRectangular**: Left-aligned stack — `"💚 Alex"` (headline), `"Available"` (subheadline), `"miss you"` (caption, truncated). Maximum information density.

**systemSmall**: Centered layout — emoji (36pt), name (headline), status (caption). Glass container background on iOS 26. Not-connected: heart icon + "Not Connected."

**systemMedium**: Horizontal layout — emoji (44pt) left, text stack right (name, status, message 2-line, timestamp). This is the flagship widget — room for the full experience. Not-connected: heart icon + "Open app to connect."

### watchOS Smart Stack (Relevant Widget)

Uses `RelevanceEntriesProvider`. Surfaces when partner's status changes. Same layout as accessoryRectangular but optimized for watch glance.

---

## Platform-Specific Notes

### iOS 26
- Full Liquid Glass adoption
- Mesh gradient backgrounds
- Morphing sheet presentations
- SF Symbol effects throughout

### watchOS 26
- Simplified connected view (read-only for v1)
- Glass button for quick status change (future: Control)
- Smaller type scale (watch-appropriate)
- No mesh gradient (performance)

### macOS Tahoe
- Sidebar-free single-window app
- Desktop widget support (systemSmall, systemMedium)
- Notification Center integration
- Keyboard shortcuts for status change

### iPadOS 26
- Same as iOS, responsive layout
- Larger partner card on wider screens

---

## What Good Looks Like (Reference Apps)

| App | What to learn | What to avoid |
|---|---|---|
| **Locket** | Widget-first philosophy. App is minimal, widget is the product. Dark + warm yellow accent. Camera as hero. | Can feel too photo-centric for our use case |
| **Mubr** | Clean dark UI, neon-ish accents, good use of music visualizations as ambient animation | Overcomplicates the sharing model |
| **Widgetable** | Huge widget variety shows what's possible | Feature bloat, ad-driven UX, cluttered navigation |
| **Apple Weather** | Best-in-class animated backgrounds (mesh gradients for conditions), Liquid Glass adoption | — |
| **Apple Music** | Animated album art backgrounds, glass now-playing bar, warm colors extracted from content | — |
| **Flighty** | Widget-first flight tracker. In-app is detailed, widget is glanceable. Beautiful data viz. | Over-designed for our simpler use case |

---

## Implementation Priority

1. **Color system** — Define `FondColors` in an asset catalog + Swift extension
2. **Connected view redesign** — Partner card + mesh gradient + glass controls
3. **Animation layer** — Mesh gradient, symbol effects, spring transitions
4. **Widget Liquid Glass** — `widgetRenderingMode` handling
5. **Onboarding polish** — Welcome screen, pairing flow, widget tutorial
6. **History sheet** — Chat-bubble redesign with warm colors
7. **Settings sheet** — Minimal glass-styled list
8. **watchOS views** — Simplified connected view

---

*This is a living document. Update as design decisions evolve during implementation.*
