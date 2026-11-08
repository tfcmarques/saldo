# Saldo design system

Saldo should feel like a premium banking product: calm, precise and trustworthy.
Complex money information should be effortless to read and act on.

**Less decoration, more clarity.** Every element earns its place by helping someone
understand or move their money.

All tokens and shared components live in
[`Sources/Saldo/DesignSystem.swift`](../Sources/Saldo/DesignSystem.swift). Views use
`DS.*` and the components below. They never hard-code colours, sizes or radii.

## Principles

- Neutral first. Most of the interface is black, white and greys. Colour carries meaning.
- Figures lead. Balances and totals are the largest, clearest thing on a screen.
- Group, don't box. Put related content on one grouped surface instead of a card per item.
- One way to do each thing. The same action looks the same on every screen.
- Light and dark are both first-class. Dark mode is designed, not inverted.

Avoid gradients (one exception, below), heavy shadows, decorative illustrations, extra
accent colours, mixed corner radii and oversized type.

**No separator glyphs.** Never join text with a middle dot (·), a vertical bar (|), or an
en or em dash (– —). Put related facts side by side with `DetailLine`, which separates
them with space and tone. Use words ("Net across 24 entries", "Since 3 May"), parentheses
("−€421,49 (0,8%)"), or "n/a" for a missing value.

## Colour (`DS.Palette`)

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#FFFFFF` | `#000000` | Page background |
| `surface` | `#F4F4F4` | `#16181A` | Grouped areas, cards |
| `surfaceSubtle` | `#F7F7F7` | `#1C1E21` | Sidebar |
| `surfaceRaised` | `#FFFFFF` | `#242629` | Selected sidebar row, tooltips |
| `border` | `#E2E2E7` | `#2A2D31` | Dividers, chart gridlines |
| `textPrimary` | `#191C1F` | `#FFFFFF` | Main content, figures |
| `textSecondary` | `#505A63` | `#A0A4AA` | Labels, supporting text |
| `textMuted` | `#8D969E` | `#70767D` | Metadata, axis labels |
| `accent` | `#494FDF` | `#6E73F2` | Focus, selection, the net worth chart |
| `accentHover` | `#4F55F1` | `#8287F5` | Hover on accent controls |
| `success` | `#00A87E` | `#1FC497` | Money in, growth |
| `warning` | `#EC7E00` | `#FF9A2E` | Scheduled items, missing data |
| `danger` | `#E23B4A` | `#FF5C69` | Negative balances, errors, deletion |
| `inverse` / `onInverse` | `#191C1F` / white | white / `#191C1F` | Primary buttons, initials avatar |

Rules:
- Incoming money is `success` with a `+` sign. Outgoing money stays `textPrimary` with a `−`.
- A negative balance is `danger`. Nothing else turns red.
- `accent` is for interaction and emphasis, never decoration.
- Account and category colours come from the user's choice (`PaletteColor`). Show them only
  inside an `IconBubble` or a chart series.

## Typography (`DS.Typeface`)

San Francisco, the system font. All money uses tabular figures (`.monospacedDigit()`;
`MoneyText` does this for you).

| Token | Size / weight | Use |
|---|---|---|
| `display` | 40 semibold, tracking −0.5 | The one hero figure per screen (net worth) |
| `pageTitle` | 26 semibold | `PageHeader` title |
| `figure` | 26 semibold | Key figures in a stats strip, ledger net |
| `title1` | Title semibold | Detail headings (a debt's name) |
| `title2` | Title 2 semibold | Rarely; prefer `title3` |
| `title3` | Title 3 semibold | Card titles, account balances |
| `body` / `bodyStrong` | Body / medium | Rows, buttons |
| `small` | Callout | Secondary lines, search |
| `caption` | Caption | Metadata, captions, badges |
| `micro` | Caption 2 | The smallest labels, like "Registered Mac user" |

## Spacing (`DS.Space`)

4-point scale: `xxs` 4, `xs` 8, `s` 12, `m` 16, `l` 24, `xl` 32, `xxl` 48.
Page content uses `xl` side margins. Sections are `l` to `xl` apart.

## Radius (`DS.Radius`)

`small` 8 (tooltips), `control` 12 (sidebar rows, inputs), `card` 16 (surfaces, account
cards), `large` 20.
Buttons, badges and search are capsules. Always use `.continuous` corners.

## Motion (`DS.Motion`)

`quick` is a 180 ms ease-out, for hover, press and focus. Nothing else animates by default.

## Components

| Component | What it is | Use it for |
|---|---|---|
| `PageHeader` | Large title on the left, pill actions on the right | The top of every section, attached with `.safeAreaInset(edge: .top)` |
| `.surface()` | Padded `surface` fill, `card` radius, no border or shadow | Any grouped area. `dashboardCard()` is an alias |
| `.pageBackground()` / `.pageList()` | Page background for plain views and for lists | Every section root |
| `PillButtonStyle` (`.pill(...)`) | Capsule button: `.primary` (dark), `.secondary` (grey), `.tertiary` (clear), `.accent`, `.destructive` (red tint) | Every text button, including sheet Cancel (secondary) and confirm (primary) |
| `IconButtonStyle` (`.icon`) | 28 pt round icon-only button with hover fill | Row actions: edit, delete, mark as paid |
| `PillPicker` | A secondary pill that opens a native menu: header, checkmark, icons, an "All" option above a divider | Filters, time ranges, chart grouping. Never the system pop-up button |
| `SearchField` | Capsule text field with accent focus ring | Ledger search (⌘F focuses it) |
| `StatusBadge` | Small tinted capsule with optional icon | "Scheduled", change in net worth |
| `IconBubble` | Outline symbol on a 14 % tint circle | Accounts, categories, debts, transfers |
| `MoneyText` | Currency in tabular figures, optional sign and colour | Every amount in a row |
| `TransactionRow` | `IconBubble`, title over a `DetailLine`, `MoneyText` on the right | Ledger, recent activity |
| `SectionLabel` | Semibold secondary label | Day headers, small section titles |
| `DetailLine` | Secondary facts side by side; the first in `textSecondary`, the rest in `textMuted` | Any subtitle with more than one fact, instead of separator glyphs |
| `UserAvatar` | The Mac account picture, or initials on `inverse` | Sidebar, anywhere the owner appears |
| `.formHint()` | Caption in `textSecondary` | The explanation under a form field |
| `quietYAxis()` | Dashed `border` gridlines, `textMuted` labels | Every chart's y axis |

Icons are SF Symbols in their outline form. `IconBubble` drops a stored `.fill` suffix
when an outline version exists (`Symbol.outline`).

## Layout

- **Window.** Opens filling the screen as a normal window (not a full-screen Space), so
  the close, minimise and zoom buttons stay visible top left. Hidden title bar, flat
  full-height sidebar (232 pt, `surfaceSubtle`, 1 pt `border` divider), content on
  `background`. There is no floating sidebar and no window toolbar. Actions live in each
  page's `PageHeader`.
- **Top inset.** The sidebar brand and every page title start `DS.Layout.chromeTop` (44 pt)
  from the top, in a window and in full screen alike, so they line up and clear the window
  buttons.
- **Controls sit next to what they change.** A filter or time range goes beside the chart
  or list it affects, not in the page header. The dashboard's time range lives in the
  Balance history card.
- **Sidebar.** Main sections at the top, then Settings and Lock at the bottom, then the
  owner's avatar and name. The selected row is `surfaceRaised` with `textPrimary`;
  others are `textSecondary`.
- **Dashboard.** Greeting, then net worth in `display` with a change badge, then pill
  actions, then one stats strip (Available cash, Left this month, debts) split by
  dividers. Account cards, charts and summaries follow, and stack when the window narrows.
- **Accounts page.** Open accounts, closed accounts, then debts, in one list. A debt
  opens its details and payments in a sheet. There is no separate Debts page.
- **Categories.** Managed from the Ledger (More, then Categories), next to the entries
  that use them, in a sheet listing each category with its entry count. Not in Settings.
- **Bills page.** A monthly checklist, not ledger entries. A summary surface shows
  Available cash, Still to pay and Left this month, with a progress bar of bills handled.
  Bills are split into "Still to pay" and "Paid or skipped this month"; clicking a row
  ticks it. Ticks clear on the 1st.
- **Lists.** Rows are `TransactionRow` or close to it: amounts right-aligned, subtle
  separators. The ledger groups entries by day ("Today", "Yesterday", "Friday,
  6 November") with each day's net on the right.
- **Sheets.** See below.

## Sheets

- Native grouped `Form` on the page background (`.pageList()`), 440 pt wide, tinted with
  `accent`. Cancel is a secondary pill, the confirm button a primary pill.
- One sheet both adds and edits (`AccountSheet`, `DebtSheet`, `BillSheet`). The title and
  confirm button change ("New account" with Add, "Edit account" with Save).
- Field order: what it is (name, type, direction), then currency, then the amount, then
  Description, then the date. Appearance (icon, colour) and Options (toggles) go in their
  own sections below.
- The free-text field is always "Description". Amount labels always name the currency:
  "Opening balance (EUR)".
- Explain a field with `.formHint()` under it. Don't repeat the same text as a tooltip.
- Show the consequence before it happens: the gain or loss an update creates, what is left
  on a debt, the converted amount of a transfer.

## Tooltips

Every action outside a sheet has a `.help` tooltip: pills, icon buttons, menus, pickers
and clickable rows. Say what happens in plain words and add the shortcut when there is
one: "Record income or an expense (⌘N)". Sheet Cancel and confirm buttons need none.

## Menus

Menus show a header (the picker's title), a checkmark on the current choice, and the item's
outline icon when it has one (accounts, categories). Pickers inside sheets show the same
icons. Put "All …" first, above a divider.

## System surfaces

Menus, alerts, confirmation dialogs and `.help` tooltips stay native, tinted by `accent`.
Saldo does not imitate them. Its own floating surfaces (chart tooltips, the colour popover)
use `surfaceRaised`, a `border` outline and `Radius.small`.

Confirm before anything that cannot be undone (deleting an account, a debt, a bill or a
category, restoring a backup, deleting all data). Deleting entries needs no confirmation
because ⌘Z brings them back.

## Charts

- Minimal: dashed gridlines on the y axis only, muted labels, no point markers.
- Balances use step lines (`.stepEnd`), 2 pt with round caps. The y axis does not have
  to start at zero.
- The default balance chart is a single net worth line in `accent` over a soft accent
  fade. This is the only gradient in the app. Account and type breakdowns are optional
  groupings.
- Income bars are `success`, expense bars are `danger`, with 3 pt corners.
- Closed accounts never appear on a chart. Their balance still counts in totals.
- Tooltips are `surfaceRaised` with a `border` outline, no shadow.

## Accessibility

- Keep body text at `textSecondary` or stronger on `background` and `surface`.
- Icon-only buttons always have a text label (`Button("Edit", systemImage:)` with
  `.icon`) and a `.help` tooltip.
- Colour is never the only signal: income also gets a `+`, scheduled items get a badge.

## Adding UI

1. Reach for an existing component first.
2. If you need a new value, add a token to `DS` instead of a literal in the view.
3. If a pattern repeats on two screens, make it a component in `DesignSystem.swift` and
   list it here.
