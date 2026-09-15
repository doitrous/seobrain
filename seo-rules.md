# SEO rules for the weekly run

Every agent reads this file before doing anything. The hub's deterministic audit enforces the numeric rules below; the rest are judgment rules the auditor checks.

## Payload contracts

Files live in `runs/<date>/job-<id>/`. Every JSON file is posted to the hub verbatim, so keys must match exactly.

- `topic.json` (topic-scout → orchestrator): `{ "title", "keyword", "market", "lang", "source": "discovered", "intent": "informational|commercial|transactional", "pageType", "hubRole"?, "rationale" }`. See Page types below for how `pageType` is assigned — by topic-scout, a queued-topic row, or (v2 phase 4) copied straight from a hub-approved brief when the job is `{"siteId","briefId"}` — and its Writer modes by page type subsection for what the writer then does differently. `hubRole` (v2 phase 8, optional) is `"pillar"|"member"|null` and exists only on a brief-based job: `scripts/hub.sh briefs <SITE_ID>` (`GET /api/briefs?siteId&status=approved`) returns each approved brief with `pageType`, `hubRole` and `hubId`, and the orchestrator copies both `pageType` and `hubRole` from the brief into `topic.json` when it creates that job. A scout-discovered or queued-topic job never carries `hubRole` — leave the key out rather than writing `null`.
- `research.json` (researcher): `{ "searchIntent", "facts": [{ "claim", "source_url", "quote", "asOf" }], "competitorHeadings": [{ "url", "headings": [] }], "peopleAlsoAsk": [], "gaps": [], "localAngle" }`. `asOf` (v2 phase 4) is the month and year the fact is current as of — "March 2026" — taken from the source's own dated content when it has one, otherwise the month/year you fetched it. This is the same shape the hub's brief `sources[]` uses (`{url, quote, claim}`, `asOf` folded into the claim sentence as "as of <month year>") — a `facts[]` entry is a `sources[]` entry with the research-stage field names.
- `outline.json` (writer): `{ "h1", "sections": [{ "h2", "h3s": [], "purpose" }], "targetWords", "primaryKeyword", "secondaryKeywords": [], "faqQuestions": [], "internalLinks": [{ "title", "slug" }] }`
- `draft.json` (writer, also the article payload): `{ "lang", "title", "metaTitle", "metaDescription", "slug", "bodyMd", "keyword", "targetWords", "introduction", "secondaryKeywords": [], "searchIntent", "og": { "title", "description" }, "references": [{ "title", "url", "publisher", "date" }], "faq": [{ "q", "a" }], "internalLinks": [{ "title", "slug" }], "schemaJsonld": [], "hreflang": {} }`. Medical sites also carry `"sections": { "<safety key>": { "heading": "<the exact H2 text in bodyMd>" } | { "omitted": true, "reason": "…" } }`, one entry for each of the four safety keys. The **writer** produces it: the hub reads `sections` from the `draft` step when it audits, and stores it on the article when the draft is posted as the primary article. The auditor verifies that map against `bodyMd` and copies the verified version into `checklist.json.sections`, which the hub uses when the article payload carries none.
- `image_brief.json` (writer): `{ "prompt", "search_terms": [], "alt", "filename" }`
- `checklist.json` (auditor, medical sites only): `{ "items": { "<item key>": { "complete": true|false, "omitted": true|false, "reason": "…", "evidence": "quoted sentence from the draft" } }, "sections": { "who_may_benefit": { "heading": "<exact H2 text>" } | { "omitted": true, "reason": "…" }, … } }`
- `audit.json` (auditor): `{ "pass", "readiness": "critical|needs_improvement|ready", "issues": [{ "code", "severity": "critical|warning", "message" }], "source": "combined", "deterministic": <hub result>, "eeat": { "pass", "notes": [] } }`
- `article-<lang>.json` (localizer): same shape as `draft.json` with that `lang`. Medical sites: also carry `"sections"` — the auditor's `checklist.json.sections` (falling back to `draft.json.sections` when the job has no checklist) with each `heading` re-pointed to the translated H2 text in this language's `bodyMd` (omitted entries copied as they are). Without it the hub cannot verify the translated safety sections.

## Writing rules

- `introduction` is a separate field, not the first paragraph of `bodyMd`. Write it as 40–60 words (Arabic 30–60) that answer the search intent, contain the primary keyword in the same word order, and read as the article's opening. Its **first sentence starts with the primary keyword**. `bodyMd` still opens with a paragraph after the H1 — the introduction field is what the site renders as the lede and what the hub falls back to for `meta_description` and the OG description.
- **Arabic note:** MSA sentences are often verb-initial or topic-fronted rather than noun-first. A verb-initial or topic-fronted sentence still satisfies "starts with the keyword" as long as the keyword phrase opens the first clause — it does not have to be the literal first word.
- When the job has a `pillar` required link (its `pageType` needs one, or a hub-approved brief names one), the intro also bolds and links the pillar's own keyword to its slug inside `introduction` or `bodyMd`'s first paragraph — `**[<pillar keyword>](/blog/<lang>/<pillar-slug>)**`. Missing this trips the hub's `intro_pillar_link` warning.
- Every factual, numeric, medical, legal, price, or travel claim must trace to a `facts[]` entry from `research.json`. If no fact supports it, do not write it. Cite sources inline as markdown links on the claim.
- Concrete over generic: named clinics, districts, prices with currency and year, procedure names, durations. No filler ("in today's fast-paced world").
- Paragraphs: 2–4 sentences. One bolded keyword or related term per **prose paragraph of ≥ 2 sentences**, varied — never the same word bolded twice in a row. "Paragraph" here means a body prose paragraph only: list items, table cells, headings, FAQ answers and the `introduction` field are excluded from the count either way. Fewer than half the eligible prose paragraphs bolded trips `bold_per_paragraph` (warning). Use H2 every 150–300 words. Bulleted lists for steps, options, checklists. One comparison table where two or more options are compared.
- Every content image embedded in `bodyMd` carries a caption: markdown `![alt](src "caption text")` — the site renders the title string as the `<figcaption>`. An image with no caption trips `caption_missing` (warning).
- Blog titles may lead with a number where it reads naturally ("10 Tips Before Travelling to Egypt") for informational posts (`pageType` `cluster`/`guide`, or no `pageType` with an informational intent) only — never on `procedure`, `cost` or `help` titles. This is a writer judgment call only; the hub does not audit it.
- Long pillar or blog pages may present sections as accordions: 4–5 visible H2 headings, every section's content already present in `bodyMd` (server-rendered, not fetched on click). Never write layout or interaction instructions into the text itself ("click to expand", "tap to see more").
- Tone comes from the site brief and `rules`. Never claim guarantees or outcomes. Lines in `rules` starting with `never:` are banned phrases; the hub audit fails the draft if they appear.
- Do not mention AI, the writing process, or "this article".

## Keyword rules

- One primary keyword per article (from `topic.json.keyword`). It appears in: title, H1, the `introduction` field, at least one H2, meta description, slug. The old "first 100 words of the body" rule is gone — the hub checks the keyword against `introduction` (`intro_keyword`, critical), not the opening of `bodyMd`.
- The hub checks keyword placement as a contiguous phrase, ignoring punctuation and English function words (a, an, the, in, on, at, for, of, to, and, or, with, from, by, vs). So the keyword `hair transplant egypt uk patients` is satisfied by "Hair transplant in Egypt for UK patients" but not by "hair transplant for patients from the UK in Egypt". Topic-scout must choose keywords that read naturally as one phrase; writers must keep that word order wherever the keyword is required.
- The slug is derived once from the topic keyword (ASCII) and shared by every language version. A localized version's `keyword` is the native-language term used for title/H1/H2/meta/body placement only; it never changes the slug. Keep primary-keyword density **at or under 4%** of the body words — the hub warns on `keyword_stuffing` above that; never awkward repetition.
- 3–6 secondary keywords from research (People Also Ask, competitor headings, autocomplete) used naturally in H2/H3s and body.
- Meta title 45–60 characters (Arabic: 39–70); aim 50–58 for English — the hub warns `title_length_aim` above 58. Meta description 130–155 characters, Arabic 110–180. Meta title ≠ H1 wording exactly; it may add a hook ("2026 guide", "costs & clinics").

## Search intent

`searchIntent` on every article is one of the five Aspects values. Map the topic's `intent` like this:

| `topic.json.intent` | `searchIntent` on the article |
|---|---|
| `informational` | `informational` |
| `commercial` | `commercial_investigation` |
| `transactional` | `booking_transactional` |

The topic-scout's `intent` is advisory: the writer sets `local` when the keyword names a city, area or clinic, and `navigational` when it names a brand or a specific page; otherwise it uses the mapping above. Never invent a sixth value.

## Page types

Topic-scout sets `pageType` on every discovered topic — one of `pillar, cluster, procedure, tour, cost, comparison, alternative, constraint, help, guide, tool, author, about, landing, category, product`. Pick from the keyword's shape, not the site's vertical:

| keyword/title shape | `pageType` |
|---|---|
| "X cost", "how much does X cost", price-led | `cost` |
| "X vs Y", "X or Y" | `comparison` |
| "alternatives to X", "best X" (a list of options) | `alternative` |
| "X for <constraint>" (age, budget, condition, nationality) | `constraint` |
| a specific procedure or trip page ("hair transplant Egypt", "Cairo day tour") | `procedure` (medical/clinic sites) or `tour` (travel sites) |
| a shop/service grouping page ("shop wedding dresses", "our services") on shop-shaped or clinic sites | `category` (v2 phase 8) |
| a single shop product or a named clinic service ("long navy blue bridesmaid dress", "FUE hair transplant package") — never a trip/tour, that's `tour` | `product` (v2 phase 8) |
| a direct question a short, sourced answer settles ("is X safe", "do I need a visa for X") | `help` |
| broad/how-it-works background with no first-party data or decision aid | `guide` — use sparingly; the hub refuses a site's 4th `guide` job in a row while it is under its bottom-funnel quota (`400 guide_quota_exceeded` from `create-job` — see Keyword collisions) |

A `queuedTopics[]` row may already carry a `pageType` (an admin or the ledger set it) — never override that one; only assign `pageType` yourself for a topic-scout-discovered topic. Pass it straight through in `create-job`'s `topic` object; the hub uses it to pick that type's template and required-links checks (see `required_links_missing` etc. below) — a topic with no `pageType` simply skips those checks. (v2 phase 4) A brief-based job (`{"siteId","briefId"}`) carries its brief's `pageType` the same way — see Writer modes by page type below.

### Writer modes by page type (v2 phase 4)

Whichever way `pageType` got set — topic-scout, a queued-topic row, or a hub-approved brief — the writer follows that type's mode in addition to every other rule in this file:

- `procedure`, `cluster`, `tour`, `guide`, `author`, `about`, `landing`, or no `pageType` at all: the base `write` procedure, unchanged.
- `cost`: a pricing table naming at least 2–3 concrete, real providers/clinics/options with currency and year, plus a short "what affects the price" section.
- `comparison`: a markdown table comparing named, real competitors or options by the reader's actual decision criteria, with **at least one row where the site/subject honestly loses or ties** — a comparison with no losses reads as an ad, not research, and fails E-E-A-T trust. Never invent a competitor or a number for one.
- `alternative`: 5–8 real alternative options (not fewer, not a wall of 20), each with a one-line "best for" and its own honest trade-off.
- `constraint`: written for a reader who may be ruled out by a specific constraint (budget, age, medical condition, timing) — lead with whether they qualify, then what to do if they don't.
- `help`: answer-first — the direct answer in the first sentence, no throat-clearing intro — matching the hub's `answer_first` help-center check.
- `tool`: write only the tool's copy (`methodologyMd`, `dataSource`, `asOf`, `faq[]`); never invent the calculator's logic/config, and never guess `dataSource`/`asOf` without a source in research.
- `pillar`: an overview that introduces and links every member of its hub (member titles/slugs come from the brief); no facts of its own beyond what is needed to summarize each member. The primary keyword appears in **at least 2 H2s** (doc 03 — more than the usual ≥ 1 H2 rule, because a pillar's sections are the member summaries themselves). `schemaJsonld` swaps `BlogPosting` for `CollectionPage` + `ItemList` of the members.
- `category` (v2 phase 8): H1 = keyword + appeal ("Shop Elegant Bridesmaid Dresses for Every Style and Season"); intro with the keyword and 1–2 natural variations; body ends with a "why us" section (reviews, policies, awards) then a longer content block (tips/care/FAQ). `schemaJsonld` swaps `BlogPosting` for `CollectionPage` + `ItemList`. Links the site's pillar page unless the job's `hubRole` is `pillar` — a category page that is itself the hub's pillar needs no separate pillar link, the same exception as the `pillar` type.
- `product` (v2 phase 8): H1 = the product/service name as the keyword ("Long Navy Blue Bridesmaid Dress"); ≥ 300 words covering what it is, who it's for, what's included/not, price with currency and an "as of" date, delivery/duration, care/recovery, FAQ. Never copy manufacturer/supplier text. Never use `product` for a trip or tour — that's the `tour` page type, always. Schema is vertical-dependent (doc 04): `schemaJsonld` swaps `BlogPosting` for `Product` + `Offer` on shop-shaped sites, or `Service` + `Offer` on clinic sites. Links: the pillar (category), 2 related products (siblings), 1 money page (booking/contact).

### Funnel stages

Each `pageType` sits in exactly one funnel stage — this is how `/api/plan`'s `funnelGap` (target minus actual job count this week, per stage, from `sites.mixTargets`) maps back onto a topic choice:

| stage | `pageType`s |
|---|---|
| `bottom` | `procedure`, `tour`, `cost`, `tool`, `landing`, `help`, `category`, `product` |
| `mid` | `comparison`, `alternative`, `constraint` |
| `top` | `guide`, `pillar`, `cluster`, `author`, `about` |

Topic-scout reads `funnelGap` from its own input file and, when ranking otherwise-similar candidates, prefers the one whose `pageType` falls in the stage with the largest gap (see its own file, step 5). Never bend a candidate into the wrong `pageType` just to hit a stage.

## Secondary keywords, OG and references

- `secondaryKeywords`: 3–6 phrases from research (People Also Ask, competitor headings, autocomplete). At least three must actually appear in `bodyMd` — the hub warns on `secondary_keywords_used` otherwise.
- `og.title` and `og.description` are both required and never empty. Title ≤ 60 characters, description 100–160; they may differ from the meta pair to read better as a social card.
- `references`: every source URL you cited in `bodyMd` from `research.json.facts[]`, as `{ "title", "url", "publisher", "date" }`. `title` and `url` are required, `publisher` and `date` are filled when research has them. Medical sites need **at least 2**, every URL **https**, and every URL must also appear inline in `bodyMd`.
- `cta`: the closing section must contain `site.cta.text` verbatim, or a markdown link to `site.cta.url` — that is what the hub's `cta_present` check looks for and it never changes. When the job's market (its `site.markets` entry, see Market rules) also sets a `cta`, add it as one more sentence or link in the same closing section, alongside the site's — never in place of it. Do not invent a CTA — use the site's and, where the market has one, the market's own text/url, never a paraphrase.

## Medical sites (`site.contentKind === "medical"`)

Everything in this section applies only when the site file says `"contentKind": "medical"`. Never guess from the brief or the rules text.

### The four safety sections

`bodyMd` must contain an H2 for each of these, using one of the listed heading forms (or a natural equivalent in the article's language):

| key | English H2 | Arabic H2 |
|---|---|---|
| `who_may_benefit` | Who may benefit | من قد يستفيد |
| `who_may_not_be_suitable` | Who may not be suitable | من قد لا يكون مناسبًا |
| `risks_limitations` | Risks and limitations | المخاطر والقيود |
| `when_to_seek_help` | When to seek medical help | متى تطلب المساعدة الطبية |

The writer records all four in `draft.json.sections`: `{ "<key>": { "heading": "<the exact H2 text in bodyMd>" } }`, or `{ "<key>": { "omitted": true, "reason": "…" } }` with a real reason ("this is a cost comparison, not a procedure page"), never a blank string, for a section that genuinely does not apply. The auditor verifies every `heading` against the H2s in `bodyMd`, corrects the map, and copies it into `checklist.json.sections`. A heading the hub cannot find in `bodyMd`, and a missing section with no reason, are both critical `safety_sections` failures.

### The 20-item checklist

The auditor fills every one of these on medical sites. All 20 are required: each must be `complete: true`, or `omitted: true` with a non-blank `reason`. The seven marked **safety** additionally need an `evidence` quote — a sentence copied verbatim from the draft that proves it.

| # | key | what "complete" means | evidence |
|---|---|---|---|
| 1 | `named_author` | The site's author is named in the byline or closing section. | — |
| 2 | `named_medical_reviewer` | `site.reviewer.name` appears in the closing "reviewed by" sentence. | — |
| 3 | `reviewer_qualifications` | The reviewer's credentials appear next to their name. | — |
| 4 | `publication_dates` | Pipeline fact: the hub stamps `published_at`, `medical_reviewed_at` and `seo_reviewed_at` at publish time and writes them into the schema. Evidence names that mechanism. | — |
| 5 | `original_patient_focused` | Written for a patient, not lifted from a clinic brochure. | — |
| 6 | `education_not_diagnosis` | **safety** — the article educates and never diagnoses. | the sentence that tells the reader to see a clinician |
| 7 | `indications_and_suitability` | **safety** — who the procedure suits is stated. | the "who may benefit" sentence |
| 8 | `alternatives` | At least one alternative option is described. | — |
| 9 | `no_guarantees` | **safety** — no guaranteed outcome, no "best", "painless", "100%". | the sentence that qualifies outcomes |
| 10 | `contraindications` | **safety** — who should not have it is stated. | the "not suitable" sentence |
| 11 | `risks_limitations` | **safety** — real risks and limits are named. | the risks sentence |
| 12 | `professional_help` | **safety** — when to seek help is stated. | the "seek help" sentence |
| 13 | `patient_privacy` | **safety** — no identifiable patient details, photos or stories. | the sentence or a note that no patient data appears |
| 14 | `reviewed_references` | Every `references[]` entry was actually read and supports a claim. | — |
| 15 | `natural_language` | Reads natively in its language; no translationese. | — |
| 16 | `links_images_metadata` | Internal links resolve, image alt is set, meta fields are filled. | — |
| 17 | `doctor_approval` | Content is consistent with the site's medical rules. | — |
| 18 | `seo_approval` | Pipeline fact: the hub re-runs the audit as a publish gate and refuses on any critical failure. Evidence names that mechanism. | — |
| 19 | `translation_status` | Every language in `site.languages` is drafted or has a recorded failure. | — |
| 20 | `publication_approval` | Nothing in the article blocks publication. | — |

Five of the 20 are evidenced by the pipeline itself, not by the text of the draft: `publication_dates`, `translation_status`, `doctor_approval`, `seo_approval` and `publication_approval`. The hub stamps the reviewer and publication dates and publishes at the close of the review window, and the localizer produces the other languages. The auditor marks these five `complete` with an `evidence` line naming that mechanism, and never raises `checklist_gap` for them.

Any other item you cannot honestly mark complete and cannot honestly omit is a judgment error `checklist_gap` in `audit.json` — do not guess. `checklist_gap` is therefore only ever about a content item, which the writer's `revise` pass can fix by adding what the item needs.

### Medical schema

Medical articles use `MedicalWebPage` instead of `BlogPosting` and must carry `"reviewedBy": { "@type": "Person", "name": "{{site.reviewer.name}}", "jobTitle": "{{site.reviewer.credentials}}" }` — the name must match `site.reviewer.name` exactly, or the hub fails `structured_data_valid`.

## Structure rules

- Exactly one H1 (= `title`). Heading levels never skip (H2 → H3, never H2 → H4).
- Word count: `targetWords` from the outline, picked by `pageType` from the table below (floor is a hard minimum — the hub's `thin_content`/`word_count` critical; target is the aim, warned when missed by > 20%; ceiling is the practical cap). A job with no `pageType` uses the informational/commercial row by `searchIntent`, with the same 300-word floor.

| `pageType` | Floor | Target | Ceiling |
|---|---|---|---|
| `pillar` | 1,000 | ~1,500 | 2,500 |
| `category` | 300 | 400–800 | 2,000 |
| `product` | 300 | 300–600 | 1,500 |
| `procedure` | 600 | 900–1,600 | 3,000 |
| `tour` | 500 | 800–1,400 | 3,000 |
| `cost` | 400 | 600–1,000 | 2,500 |
| `comparison` / `alternative` | 500 | 800–1,400 | 2,500 |
| `constraint` | 300 | 500–900 | 2,000 |
| `help` | 150 | 200–400 | 1,000 |
| `tool` | 200 | 300–600 | 2,000 |
| `author` | 50 | 150–300 | 800 |
| `about` | 100 | 300–600 | 1,500 |
| `cluster`/`guide`/no `pageType`, informational | 300 | 900–1,600 | 3,000 |
| `cluster`/`guide`/no `pageType`, commercial | 300 | 600–1,000 | 2,000 |

- FAQ block: 3–6 questions taken from People Also Ask / autocomplete, each answer 40–80 words, answer-first.
- End with a short next-step section (consultation, booking, contact) matching the site's business, no hard sell.

## Language rules

- Write natively in the target language; never translate sentence by sentence. Arabic: Modern Standard Arabic with Gulf-neutral vocabulary for SA/YE/LY readers; numbers as digits; no dialect. Greek, German, Italian, Russian: standard register, formal address (Sie/Lei/вы).
- Sentence length targets (average): en 15–20 words, ar 12–18, de 14–20, el 14–20, it 15–20, ru 12–18.
- Keep proper nouns (clinic names, Cairo districts) in Latin script in Arabic text only when there is no established Arabic form.
- Right-to-left languages: no layout instructions in the text; the site handles direction.
- **Arabic-first (v2 phase 4):** when a site's primary language (`site.languages[0]`) is `ar`, the orchestrator dispatches that job's Arabic localizer before its other languages (skill §6) so a partial run never drops the primary language. This is dispatch order only — the writer/localizer procedures for Arabic are otherwise identical to any other language.

## International angle

Each job has a `market` (ISO country code, e.g. SA, LY, YE, GR, DE, GB). The article is written for readers in that market:
- Name the market in the intro and once in an H2 where natural ("for patients from Saudi Arabia", "Ταξίδι από την Ελλάδα").
- Cover what that reader needs: flights and typical travel time to Cairo, visa notes (from research only), currency and price comparison against their home market, language support, season/timing.
- Do not fabricate visa or price facts; if research has none, say "check current requirements" and link the official source from research.

## Market rules (v2 phase 8)

Every entry in `site.markets[]` is `{ country, lang, currency?, rules?, glossary?, keywordNotes?, cta? }` and reaches this repo unchanged in `site-<SITE_ID>.json.markets`. The job's `market` (its ISO country code) selects that site's matching entry — match on `country`; if more than one entry shares that `country` (one country, several languages), take the one whose `lang` also equals the job's `lang`.

- **`rules`**: appended to the site's own `rules` — read both, and where they conflict the market's line wins. A site-level `never:` banned phrase still applies even when the market doesn't repeat it.
- **`glossary`** (`{ sourceTerm: preferredWording }`): mandatory once it exists on the job's market — a source term never appears in the body when its preferred wording exists for it; use the preferred wording every time that concept comes up. Matched case-insensitively against the article's own `lang`. The hub warns `glossary_term_ignored` when a source term slips through anyway.
- **`currency`**: shown next to any price in the body alongside the site's own currency (usually EGP) — "5,000 EGP (~650 SAR)". The hub warns `currency_mismatch` when a different currency code/symbol appears in the body without the job's own market currency alongside it.
- **`cta`** (optional `{ text, url }`): added to the closing section alongside `site.cta` when set — one more sentence or link with the market's own CTA text/URL, never a replacement for the site's (see the `cta` rule above; the hub's `cta_present` check only looks for `site.cta`, so that one always stays).
- **`keywordNotes`**: free text on how that market actually searches. Topic-scout reads it when phrasing and ranking candidate keywords for that market (see its own file), and — when otherwise-similar candidates could serve more than one market — prefers the site's market with the largest gap in topics assigned so far this batch (round-robin across `site.markets`; there is no separate hub field tracking this, it is counted locally for the run).
- **Localizer**, writing a `LANG` version rather than the job's own `market`: when `LANG` maps to exactly one entry in `site.markets`, that entry's `rules`/`glossary`/`currency`/`cta` apply. When `LANG` maps to several, the job's own `market` wins if that entry's `lang` is `LANG`; otherwise use the first `site.markets` entry whose `lang` is `LANG`.

Writer, localizer and auditor all read the job's market entry before writing or checking a word. A market with no `rules`/`glossary`/`cta` simply falls back to the site defaults for those fields — nothing extra to add.

## E-E-A-T and medical safety

- Byline is the site's `author` (name, credentials). Medical sites: include one sentence of "reviewed by {{site.reviewer.name}}, {{site.reviewer.credentials}}" in the closing section — the **reviewer**, not the author — and set `Person` schema. The hub fails `reviewer_present` (critical) when the site has no reviewer name or credentials, and `structured_data_valid` when `reviewedBy.name` does not match `site.reviewer.name` exactly.
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
- Body images beyond the hero: at least one per major H2 section on blog and pillar pages, written directly into `bodyMd` as `![alt](<slug>-<n>.jpg "caption")` — alt 8–14 words, caption one sentence summarizing or extending that section's point. The hub renders the markdown title string as the image's `<figcaption>`; an image with no caption trips `caption_missing`.

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

Medical sites (`site.contentKind === "medical"` in the site file — never inferred from the brief or the rules text): change `BlogPosting` to `MedicalWebPage` and add `"reviewedBy": { "@type": "Person", "name": "{{site.reviewer.name}}", "jobTitle": "{{site.reviewer.credentials}}" }`.

## Hreflang

`hreflang` is an object keyed by language code with the site-relative path of that version, plus `x-default` pointing at the site's first language:

```json
{ "en": "/blog/en/{{slug}}", "ar": "/blog/ar/{{slug}}", "x-default": "/blog/en/{{slug}}" }
```

List **the site's planned languages** for this article — every language this run intends to draft or localize. The hub trims the map to the languages that actually shipped before it publishes, so a version that failed drops out there and never here. `x-default` must point at one of the languages you listed. At draft time the hub warns `hreflang_reciprocal` for every language that has no stored article yet; while the localizers are still running that warning is expected and it never blocks. The writer's `hreflang` map stays plain language codes only (`en`, `ar`, `x-default`) — never write a region-coded key yourself. The hub adds `<lang>-<COUNTRY>` aliases (`ar-SA`) at publish time, next to the plain code, for every shipped language that maps to exactly one market on the site (v2 phase 8); it never adds one for a language with two or more markets.

## Audit codes

Severities are `critical` and `warning`. `pass` is false when any check is `critical`; warnings are reported and never block. `readiness` is `critical` when any critical fails, `needs_improvement` when only warnings fail, `ready` when nothing fails.

Deterministic (hub), critical: `keyword_title, keyword_h1, keyword_meta, meta_title_length, meta_description_length, h1_count, heading_skip, word_count, internal_link_count, internal_link_missing, external_http, faq_count, title_duplicate, banned_phrase, thin_content, intro_keyword, image_alt, structured_data_valid, near_duplicate_site`.
Deterministic (hub), warning: `keyword_h2, paragraph_length, keyword_stuffing, meta_description_duplicate, intro_length, secondary_keywords_used, og_fields, hreflang_reciprocal, cta_present, near_duplicate_portfolio, title_length_aim, intro_pillar_link, bold_per_paragraph, caption_missing, glossary_term_ignored, currency_mismatch`.
`near_duplicate_site`/`near_duplicate_portfolio` (v2 phase 4): simhash distance ≤ 3 against another published article on the same site (critical) or ≤ 6 across the whole portfolio (warning). Handled by the ordinary audit loop (skill §4) — see the writer's `revise` procedure for what to actually change.
New warnings (v2 phase 8) and how `revise` fixes each: `title_length_aim` — an English title over 58 characters (still ≤ 60, so not critical); shorten it, front-load the keyword tighter. `intro_pillar_link` — a job with a `pillar` required link whose pillar slug is not bolded and linked inside `introduction` or `bodyMd`'s first paragraph; add `**[<pillar keyword>](/blog/<lang>/<pillar-slug>)**` there. `bold_per_paragraph` — fewer than half of the body's ≥ 2-sentence prose paragraphs (list items, table cells, headings, FAQ answers and `introduction` are excluded from the count) contain a `**bold**` span; add one varied bold term to more of them, never the same word twice in a row. `caption_missing` — a body image markdown (`![alt](src)`) with no title string; add `"caption"` as the third part: `![alt](src "caption")`. `glossary_term_ignored` — the job's market has a `glossary` and a source term appears in the body while its preferred wording never does; replace every occurrence of the source term with the preferred wording (see Market rules). `currency_mismatch` — the market has a `currency` and the body shows a different currency code/symbol without also showing the market's; add the market currency alongside it, e.g. "5,000 EGP (~650 SAR)".
Deterministic, medical sites only — critical: `references_count, safety_sections, reviewer_present, checklist_complete`; warning: `references_in_body, checklist_safety_evidence`.
Deterministic, page-type + link graph (only on a job with `pageType` set) — critical: `required_links_missing` (the draft is missing a link its `pageType` requires; the message names exactly what — `pillar (<slug>)`, `siblings (<slug>, <slug>)`, and/or `money page (<url>)`. Fix it by adding a markdown internal link to each named slug, in the same `/blog/<lang>/<slug>` form as any other internal link, and by making sure the money page's URL literally appears in `bodyMd` — a mention or a link both satisfy it; `category` needs only `pillar` — skipped entirely when the job's `hubRole` is `pillar` — and `product` needs `pillar`, `siblings` and `money page`). Warning: `anchor_variety_low` (two or more internal links reuse the same anchor text — give each its own descriptive phrase), `template_section_missing` (the `pageType`'s template expects an H2 matching a pattern that is not present — add it), `template_schema_mismatch` (add a `schemaJsonld` entry whose `@type` matches the page type — `lib/page-types.ts` in the hub names the expected type per `pageType`, e.g. `cost` → `Service`, `comparison`/`alternative` → `ItemList`, `tool` → `WebApplication`, `pillar`/`category` → `CollectionPage`, `product` → `Product` or `Service` — vertical-dependent, see Page types), `internal_link_cap` (a *published* page has grown past 45 outbound links site-wide — nothing a single draft controls; it shows up in the hub's weekly link report, not per-job).

Judgment (auditor, severity `critical` unless noted): `unsupported_claim` (claim with no matching fact), `medical_promise` (guarantee/outcome language), `market_missing` (no market angle), `source_count` (< 2 authoritative sources), `intent_mismatch`, `checklist_gap` (a required content checklist item that can be neither completed nor omitted honestly), `translationese` (localized text reads as a translation), `faq_generic` (warning), `thin_section` (warning).

`keyword_intro` no longer exists — the keyword requirement moved from "first 100 words" to the `introduction` field as `intro_keyword`.

Expect several `audit` steps per job in the hub: the writer runs `scripts/hub.sh audit` after each draft it posts (up to three times), and each orchestrator audit loop adds the deterministic result plus the auditor's combined one. That is expected, not a bug.

On medical sites the writer's own audits run before any `checklist` step exists, so they always carry `checklist_complete` (critical) and may carry `checklist_safety_evidence`; the writer ignores those two codes because the auditor owns them. The auditor posts the `checklist` step **before** it runs `scripts/hub.sh audit`, so its own audit sees the checklist and only reports real gaps.

## Keyword collisions

One primary keyword per language per site. `scripts/hub.sh create-job` returns **HTTP 409** with `{"error":"keyword_taken","jobId":<n>}` when the keyword (normalized the same way as keyword placement) is already taken by a non-failed job on that site in that language. That is not a bug and not an agent contract violation: pick the next topic. `/api/plan` gives topic-scout each existing article's `primaryKeyword` so it can avoid the collision before asking.

`create-job` also returns **HTTP 409** with `{"error":"topic_owned_by_other_site","ownerSiteId","ownerSiteSlug","targetUrl"}` when the topic ledger already has this keyword+language `owned` by a *different* site — the hub's cross-site guard (`/api/plan`'s `blockedTopics[]` lists these in advance; drop any candidate whose normalized keyword+language matches one of them before asking topic-scout to spend a search on it). Handled exactly like `keyword_taken`: not a bug, drop the topic, pick the next one.

`create-job` also returns **HTTP 400** with `{"error":"guide_quota_exceeded"}` when the site has had 3 consecutive `guide` jobs and is under its bottom-funnel quota (`sites.mixTargets.bottom`). Drop that topic's `pageType` down to something bottom-funnel-shaped (`cost`, `procedure`/`tour`, `help`, `tool`) if the keyword supports it, or pick the next topic — never retry the same `pageType` for that slot.

## Refresh jobs

The hub queues a topic with `"source": "refresh"` and `"refreshJobId": <job id>` when a published article reaches `planned_update_at` (`published_at + site.refreshMonths`). A refresh topic is exempt from the keyword guard on purpose — the job re-uses the original keyword and slug and republishes through `adapter.update`. When a queued topic has `source: "refresh"`, create the job with `{"siteId", "topicId", "refreshOf": <topic.refreshJobId>}` and dispatch the writer with `MODE=refresh`: it fetches the published article with `scripts/hub.sh articles <JOB_ID> <FILE>` and revises that article against the research — updated facts, dates, references and safety sections — instead of writing a new one. `slug` stays byte-identical to the published article: the hub carries `remoteId`/`remoteUrl` over from the original job so the receiver updates the live post, and a changed slug would create a second post and break every internal link pointing at the old one.

## Ledger ownership and optimize-first

`/api/plan` also carries, per site: `ownedTopics` (this site's own `owned` rows in the topic ledger — `{ "normalizedKey", "language", "targetUrl" }`) and `optimizePreferred` (existing pages GSC evidence says to refresh rather than compete with a new draft — `{ "jobId", "slug", "lang", "query", "position" }`).

- **`ownedTopics`**: a keyword this site has already claimed, whether or not it has a published article yet. Topic-scout adopts any entry not already covered by `existingArticles`/`queuedTopics` before it spends a single search — see its own file, step 0. There is no collision risk (the ledger already says this site owns it), so it always beats a discovered candidate for the same slot.
- **`optimizePreferred`**: a *published* page whose own keyword is showing up at striking distance in Search Console. Refreshing it is cheaper and more likely to move the needle than a new page competing for the same intent. The orchestrator creates the refresh job directly from the entry (`refreshOf: entry.jobId`, `topic.source: "refresh"` — see SKILL.md §1) instead of asking topic-scout to discover that query; topic-scout drops any candidate matching one so the same query never becomes two jobs.
