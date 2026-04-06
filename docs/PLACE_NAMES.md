# Woleh — Place name normalization

This document is the **canonical specification** for how place names are normalized before **comparison and matching**. The rules are **domain-neutral** (same algorithm for any app on the shared backend). **Woleh** uses them for **transit** contexts—stops, landmarks, terminals—typed by users as plain strings.

It applies to drive-through lists, watch lists, and any server-side logic that decides whether two place names refer to the same place for matching purposes.

**Authority:** The **server** applies this algorithm for all matching decisions. The **mobile** app should use the **same** function for local preview (e.g. showing whether a name might match) so UX matches server behavior—never rely on client-only normalization for security or billing.

**Related:** [ARCHITECTURE.md](./ARCHITECTURE.md) §5.6, [PRD.md](./PRD.md) FR-P3.

---

## 1. Normalization pipeline (v1 — baseline)

Apply the following steps **in order** to the input string. If a step receives an empty string, subsequent steps operate on empty; the result may be empty (invalid or ignorable name—product rules may reject empty entries).

| Step | Name | Rule |
|------|------|------|
| 1 | **Trim** | Remove leading and trailing **whitespace** characters. Whitespace is Unicode-aware: includes space, tab, newline, and other characters with the Unicode `White_Space` property. |
| 2 | **Unicode NFC** | Normalize the string to **Unicode Normalization Form C** (NFC). Ensures the same logical text from different keyboards or IMEs compares equal (e.g. composed vs decomposed accents). |
| 3 | **Case folding** | Apply **Unicode case folding** (full case folding, not locale-specific “lower” rules for a single language). Use locale **root** / language-neutral behavior where the platform exposes it. |
| 4 | **Collapse internal whitespace** | Replace every **maximal contiguous run** of whitespace characters (same definition as trim) with a **single ASCII space** (U+0020). Trim again after collapse if the platform introduces edge cases at ends. |

**Result:** `normalizePlaceName(input) → string` used only for **equality** checks and set operations (intersection, deduplication). Do not use this normalized string as the only stored display value unless product decides to show the canonical form—see §4.

### 1.1 What is explicitly *not* in v1

These are **out of scope** for the baseline pipeline unless added in a later version and documented here:

- Stripping punctuation (`. , ' -` etc.)
- Removing diacritics
- NFKC / compatibility decomposition (can change semantics—avoid unless needed)
- Phonetic or fuzzy matching (edit distance) as part of **primary** match
- Alias / synonym tables

Optional follow-ups belong in a new version section or ADR when introduced.

---

## 2. Equality and matching

- **Name equality:** Two place names **match** if and only if  
  `normalizePlaceName(a) == normalizePlaceName(b)` (character-by-character equality after normalization).
- **List overlap:** When computing whether a broadcast path and a watch list overlap, compare **normalized** forms (e.g. intersection of normalized sets, or pairwise equality per product rule for ordered vs unordered lists—see PRD open questions).
- **Deduplication:** Within a single list, treat duplicates using normalized equality if product requires unique display names.

---

## 3. Implementation notes

- **Single implementation per platform** is not enough for correctness—**behavior must match**. Add **shared test vectors** (§5) in both server and mobile unit tests.
- **Java (server):** Use `java.text.Normalizer` with `Normalizer.Form.NFC` for step 2. For case folding, prefer APIs that perform **Unicode case folding** (e.g. `String` methods aligned with `Locale.ROOT` where appropriate, or a small library if the JDK’s behavior is insufficient for your minimum Java version—verify against test vectors).
- **Dart (Flutter):** Use a vetted approach for NFC and case folding (e.g. `characters` / ICU-backed packages or platform glue if available). Do not assume `toLowerCase()` alone equals full Unicode case folding for all scripts; validate with §5.

---

## 4. Storage vs display

- **APIs** may accept and return **user-entered** strings for display.
- **Matching** must always use `normalizePlaceName` for comparisons.
- If you persist only one copy, either store raw and normalize on read for matching, or store normalized for matching and raw for display—document the choice in the API schema.

---

## 5. Test vectors (must pass)

Use these as unit tests on both client and server (expected: after full pipeline, left and right produce the same string for equality purposes).

| Input A | Input B | Expected |
|---------|---------|----------|
| `"  Accra  "` | `"accra"` | Equal after normalization |
| Decomposed “é” (e + combining acute) vs precomposed “é” (U+00E9) | Same display | Equal after NFC (then case fold if applicable) |
| `"Main  St"` | `"Main St"` | Equal (internal whitespace collapsed) |

Add locale-specific edge cases as you discover them in production (e.g. Turkish `I`/`i` if users type Latin-only).

---

## 6. Versioning

| Version | Date | Summary |
|---------|------|---------|
| 1.0 | 2026-04-06 | Baseline: trim → NFC → case fold → collapse internal whitespace |

Bump version when the pipeline changes; migration may be needed for stored comparisons.
