# SEO rules for the weekly run

Every agent reads this file before doing anything. The hub's deterministic audit enforces the numeric rules below; the rest are judgment rules the auditor checks.

## Payload contracts

Files live in `runs/<date>/job-<id>/`. Every JSON file is posted to the hub verbatim, so keys must match exactly.

- `topic.json` (topic-scout → orchestrator): `{ "title", "keyword", "market", "lang", "source": "discovered", "intent": "informational|commercial|transactional", "rationale" }`
- `research.json` (researcher): `{ "searchIntent", "facts": [{ "claim", "source_url", "quote" }], "competitorHeadings": [{ "url", "headings": [] }], "peopleAlsoAsk": [], "gaps": [], "localAngle" }`
- `outline.json` (writer): `{ "h1", "sections": [{ "h2", "h3s": [], "purpose" }], "targetWords", "primaryKeyword", "secondaryKeywords": [], "faqQuestions": [], "internalLinks": [{ "title", "slug" }] }`
- `draft.json` (writer, also the article payload): `{ "lang", "title", "metaTitle", "metaDescription", "slug", "bodyMd", "keyword", "targetWords", "faq": [{ "q", "a" }], "internalLinks": [{ "title", "slug" }], "schemaJsonld": [], "hreflang": {} }`
- `image_brief.json` (writer): `{ "prompt", "search_terms": [], "alt", "filename" }`
- `audit.json` (auditor): `{ "pass", "issues": [{ "code", "severity": "error|warn", "message" }], "source": "combined", "deterministic": <hub result>, "eeat": { "pass", "notes": [] } }`
- `article-<lang>.json` (localizer): same shape as `draft.json` with that `lang`.

## Writing rules

- Answer the search intent in the first paragraph (40–60 words), then expand. The first paragraph must contain the primary keyword naturally.
- Every factual, numeric, medical, legal, price, or travel claim must trace to a `facts[]` entry from `research.json`. If no fact supports it, do not write it. Cite sources inline as markdown links on the claim.
- Concrete over generic: named clinics, districts, prices with currency and year, procedure names, durations. No filler ("in today's fast-paced world").
- Paragraphs: 2–4 sentences. Use H2 every 150–300 words. Bulleted lists for steps, options, checklists. One comparison table where two or more options are compared.
- Tone comes from the site brief and `rules`. Never claim guarantees or outcomes. Lines in `rules` starting with `never:` are banned phrases; the hub audit fails the draft if they appear.
- Do not mention AI, the writing process, or "this article".

## Keyword rules

- One primary keyword per article (from `topic.json.keyword`). It appears in: title, H1, first 100 words, at least one H2, meta description, slug.
- The slug is derived once from the topic keyword (ASCII) and shared by every language version. A localized version's `keyword` is the native-language term used for title/H1/H2/meta/body placement only; it never changes the slug. Never more than ~1% density; never awkward repetition.
- 3–6 secondary keywords from research (People Also Ask, competitor headings, autocomplete) used naturally in H2/H3s and body.
- Meta title 45–60 characters, meta description 120–160 (Arabic: 38–70 and 102–188). Meta title ≠ H1 wording exactly; it may add a hook ("2026 guide", "costs & clinics").

## Structure rules

- Exactly one H1 (= `title`). Heading levels never skip (H2 → H3, never H2 → H4).
- Word count: `targetWords` from the outline, 900–1,600 for informational, 600–1,000 for commercial pages; body must land within ±20%.
- FAQ block: 3–6 questions taken from People Also Ask / autocomplete, each answer 40–80 words, answer-first.
- End with a short next-step section (consultation, booking, contact) matching the site's business, no hard sell.

## Language rules

- Write natively in the target language; never translate sentence by sentence. Arabic: Modern Standard Arabic with Gulf-neutral vocabulary for SA/YE/LY readers; numbers as digits; no dialect. Greek, German, Italian, Russian: standard register, formal address (Sie/Lei/вы).
- Sentence length targets (average): en 15–20 words, ar 12–18, de 14–20, el 14–20, it 15–20, ru 12–18.
- Keep proper nouns (clinic names, Cairo districts) in Latin script in Arabic text only when there is no established Arabic form.
- Right-to-left languages: no layout instructions in the text; the site handles direction.

## International angle

Each job has a `market` (ISO country code, e.g. SA, LY, YE, GR, DE, GB). The article is written for readers in that market:
- Name the market in the intro and once in an H2 where natural ("for patients from Saudi Arabia", "Ταξίδι από την Ελλάδα").
- Cover what that reader needs: flights and typical travel time to Cairo, visa notes (from research only), currency and price comparison against their home market, language support, season/timing.
- Do not fabricate visa or price facts; if research has none, say "check current requirements" and link the official source from research.

## E-E-A-T and medical safety

- Byline is the site's `author` (name, credentials). Medical sites: include one sentence of "reviewed by <author>, <credentials>" in the closing section and set `Person` schema.
- Medical content: describe procedures, risks, recovery honestly; recommend a consultation; never diagnose; never promise results; no "best", "painless", "100%".
- Cite at least 2 authoritative external sources (official bodies, peer-reviewed, established medical or tourism authorities) from research, https only.

## Internal links and slugs

- Slug: lowercase, ASCII, hyphens, ≤ 60 chars, contains the primary keyword's main words, no stop words at the ends. All language versions share the primary slug.
- Internal links: from `existingArticles` for the same site, prefer the same language; 2–4 links when the site has ≥ 2 articles, otherwise as many as exist (0 or 1). Link with descriptive anchor text inside a sentence, path `/blog/<lang>/<slug>`. Never link to the article itself.

## Image brief

- `prompt`: one photoreal scene, 25–40 words, no text in image, no faces of identifiable people, matches the site (clinic interior, Cairo skyline, Red Sea resort, consultation room), style "editorial photograph, natural light".
- `search_terms`: 3–5 stock-search phrases.
- `alt`: 8–14 words describing the image and containing the primary keyword once.
- `filename`: `<slug>-hero.jpg`.

## Schema templates

`schemaJsonld` is an array. Fill `{{...}}` from the site and article. Omit any object whose data is missing.

```json
[
  { "@context": "https://schema.org", "@type": "BlogPosting", "headline": "{{title}}", "description": "{{metaDescription}}", "inLanguage": "{{lang}}",
    "author": { "@type": "Person", "name": "{{author.name}}", "jobTitle": "{{author.credentials}}", "description": "{{author.bio}}", "image": "{{author.photoUrl}}" },
    "publisher": { "@type": "Organization", "name": "{{site.name}}", "areaServed": ["{{markets[].country}}"] },
    "mainEntityOfPage": "/blog/{{lang}}/{{slug}}", "datePublished": "{{today ISO date}}" },
  { "@context": "https://schema.org", "@type": "FAQPage",
    "mainEntity": [ { "@type": "Question", "name": "{{faq.q}}", "acceptedAnswer": { "@type": "Answer", "text": "{{faq.a}}" } } ] }
]
```

Medical sites (brief or rules mention clinic, doctor, treatment, surgery, dental, hospital): change `BlogPosting` to `MedicalWebPage` and add `"reviewedBy": { "@type": "Person", "name": "{{author.name}}", "jobTitle": "{{author.credentials}}" }`.

## Hreflang

`hreflang` is an object keyed by language code with the site-relative path of that version, plus `x-default` pointing at the site's first language:

```json
{ "en": "/blog/en/{{slug}}", "ar": "/blog/ar/{{slug}}", "x-default": "/blog/en/{{slug}}" }
```

Include every language in the site's `languages` list, whether or not its localized version exists yet (they share the slug). Region codes (`ar-SA`) come in phase 4.

## Audit codes

Deterministic (hub): `keyword_title, keyword_h1, keyword_intro, keyword_h2 (warn), keyword_meta, meta_title_length, meta_description_length, h1_count, heading_skip, word_count, paragraph_length (warn), internal_link_count, internal_link_missing, external_http, faq_count, title_duplicate, banned_phrase`.
Judgment (auditor, severity error unless noted): `unsupported_claim` (claim with no matching fact), `medical_promise` (guarantee/outcome language), `market_missing` (no market angle), `source_count` (< 2 authoritative sources), `intent_mismatch`, `translationese` (localized text reads as a translation), `faq_generic (warn)`, `thin_section (warn)`.

Each audit loop records two `audit` steps in the hub: the deterministic one from `scripts/hub.sh audit` and the auditor's combined one; that is expected.
