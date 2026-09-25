# SEO rules for the weekly run

Every agent reads this file before doing anything. The hub's deterministic audit enforces the numeric rules below; the rest are judgment rules the auditor checks.

> **Keep this file current (standing rule).** This is the SEO structure/rulebook of record. Whenever the SEO flow changes — a new hub contract version, a new `pageType`, a new audit code, a changed payload field, a new writer mode, or any new SEO practice we adopt — update this file **in the same change** so it never drifts from what the hub actually does. A rule that lives only in someone's head or in a commit message is a rule the agents cannot follow. When you touch the SEO system, check this file against the hub contract (`seo-hub/docs/contracts/README.md`) and reconcile.

## Payload contracts

Files live in `runs/<date>/job-<id>/`. Every JSON file is posted to the hub verbatim, so keys must match exactly.

- `topic.json` (topic-scout → orchestrator): `{ "title", "keyword", "market", "lang", "source": "discovered", "intent": "informational|commercial|transactional", "pageType", "brief"?, "hubRole"?, "slug"?, "rationale" }`. See Page types below for how `pageType` is assigned — by topic-scout, a queued-topic row, or (v2 phase 4) copied straight from a hub-approved brief when the job is `{"siteId","briefId"}` — and its Writer modes by page type subsection for what the writer then does differently. `brief` (optional) is Omar's own idea or rough draft for the article, copied verbatim from a queued or forced topic row (`""` when that topic has none) — a non-empty `brief` makes this a refine job (writer `MODE=refine`, see Refine jobs below); a brief-based or scout-discovered job never carries one, so the key is left out rather than written as `""`. `hubRole` (v2 phase 8, optional) is `"pillar"|"member"|null` and exists only on a brief-based job: `scripts/hub.sh briefs <SITE_ID>` (`GET /api/briefs?siteId&status=approved`) returns each approved brief with `pageType`, `hubRole` and `hubId`, and the orchestrator copies both `pageType` and `hubRole` from the brief into `topic.json` when it creates that job. A scout-discovered or queued-topic job never carries `hubRole` — leave the key out rather than writing `null`. `slug` (contract 1.9.0, optional) is a pinned slug string on some brief rows — same source, copy it into `topic.json.slug` the same way as `hubRole`; a scout-discovered or queued-topic job never carries it. See Internal links and slugs, and Keyword rules, for what the writer does with a pinned slug.
- `research.json` (researcher): `{ "searchIntent", "facts": [{ "claim", "source_url", "quote", "asOf", "sourceType" }], "competitorHeadings": [{ "url", "headings": [] }], "competitors": [{ "name", "url", "note" }], "peopleAlsoAsk": [], "gaps": [], "localAngle" }`. `asOf` (v2 phase 4) is the month and year the fact is current as of — "March 2026" — taken from the source's own dated content when it has one, otherwise the month/year you fetched it. This is the same shape the hub's brief `sources[]` uses (`{url, quote, claim}`, `asOf` folded into the claim sentence as "as of <month year>") — a `facts[]` entry is a `sources[]` entry with the research-stage field names.
- `outline.json` (writer): `{ "h1", "sections": [{ "h2", "h3s": [], "purpose" }], "targetWords", "primaryKeyword", "secondaryKeywords": [], "faqQuestions": [], "internalLinks": [{ "title", "slug" }] }`
- `draft.json` (writer, also the article payload): `{ "lang", "title", "metaTitle", "metaDescription", "slug", "bodyMd", "keyword", "targetWords", "introduction", "secondaryKeywords": [], "searchIntent", "og": { "title", "description" }, "references": [{ "title", "url", "publisher", "date" }], "faq": [{ "q", "a" }], "internalLinks": [{ "title", "slug" }], "competitorLinks": [{ "name", "url", "note" }], "schemaJsonld": [], "hreflang": {} }`. `competitorLinks` is hub-only (never published) — see Link policy. Medical sites also carry `"sections": { "<safety key>": { "heading": "<the exact H2 text in bodyMd>" } | { "omitted": true, "reason": "…" } }`, one entry for each of the four safety keys. The **writer** produces it: the hub reads `sections` from the `draft` step when it audits, and stores it on the article when the draft is posted as the primary article. The auditor verifies that map against `bodyMd` and copies the verified version into `checklist.json.sections`, which the hub uses when the article payload carries none.
- `image_brief.json` (writer): `{ "prompt", "search_terms": [], "alt", "filename" }`
- `checklist.json` (auditor, medical sites only): `{ "items": { "<item key>": { "complete": true|false, "omitted": true|false, "reason": "…", "evidence": "quoted sentence from the draft" } }, "sections": { "who_may_benefit": { "heading": "<exact H2 text>" } | { "omitted": true, "reason": "…" }, … } }`
- `audit.json` (auditor): `{ "pass", "readiness": "critical|needs_improvement|ready", "issues": [{ "code", "severity": "critical|warning", "message" }], "source": "combined", "deterministic": <hub result>, "eeat": { "pass", "notes": [] } }`
- `article-<lang>.json` (localizer): same shape as `draft.json` with that `lang`. Medical sites: also carry `"sections"` — the auditor's `checklist.json.sections` (falling back to `draft.json.sections` when the job has no checklist) with each `heading` re-pointed to the translated H2 text in this language's `bodyMd` (omitted entries copied as they are). Without it the hub cannot verify the translated safety sections.

## Link policy (owner rule, 2026-09-25 — overrides any older wording in this file)

- External links in `bodyMd` and `references[]` go **only** to **research** or **government** sources:
  - research: peer-reviewed papers (PubMed/PMC, doi.org, journal sites), universities and academic medical centres, scientific or professional societies that publish guidance or data (ISHRS, AAD, ASPS, WGO, ASGE, AMA, national medical syndicates);
  - government: .gov / .gov.xx / gov.uk / nhs.uk, regulators (SFDA, MHRA, FDA, MOHP), WHO, EU, UN/World Bank/OECD data, national statistics offices, official state tourism/transport bodies (egypt.travel, enr.gov.eg).
- Never link to: competitors, marketplaces/aggregators (Bookimed, WhatClinic, TourRadar…), blogs, news media, Wikipedia, price-comparison or flight-search sites, company pages.
- **Competitors stay in the article by name** — comparisons, pricing tables and honest wins/losses are kept. Only the hyperlink goes. A figure taken from a competitor's own page is attributed in plain text ("Clinic X lists … on its website, checked September 2026").
  A competitor = any business selling the same or a substitute service/product as the site (clinics, doctors' practices, medical-tourism facilitators, tour operators/agencies, meat sellers, software agencies, course/exam-prep providers, marketplaces that sell the service).
- Every competitor page used goes into `draft.json.competitorLinks` as `{ "name", "url", "note" }` (deduplicated by URL; `note` = what it was used for). The hub keeps it on a hub-only panel, never sends it to the site, and fails `competitor_link` (critical) when the body or references link to one of those hosts.
- `research.json.facts[].sourceType` is `research`, `government`, `competitor` or `other`. Only `research`/`government` facts may carry a link; `competitor` facts are attributed by name in the text; `other` facts need a research/government source for the same claim or are softened/dropped.
- Internal links to the site's own pages are unaffected.

## Localization (owner rule, 2026-09-25 — hard requirements)

- A site has one `sourceLocale` (`site.sourceLocale`, e.g. `en-EG`). The writer writes only that version; Omar edits and approves it. Every other locale is written **after** approval by the localizer, from the approved copy (hub contract 1.17.0).
- Each localized version is a **rewrite for a reader in that country**, not a translation of the words:
  - its own native primary keyword for that locale — from `site.keywordIdeas`/`keywordVolumes` for that market when present, else from SERP research in that locale — posted as `keyword`;
  - prices in the local currency (the market's `currency`), with the source currency beside it where it helps;
  - local logistics: visa rules for that nationality, flights from that country's cities, how to get there;
  - local examples, products and items readers there know;
  - the local register and slang readers there like to read (Saudi, Egyptian, Gulf, Levantine, Maghrebi, Nigerian English, British vs American English…), professional on medical sites.
- Keep the approved version's theme, H2 order, the meaning of every claim, its tone and the CTA.
- Every new fact is researched and verified under the Link policy (research/government links only; competitors named, never linked, recorded in `competitorLinks`).
- Two versions in the same language (en-GB, en-US, en-EG) must differ substantively: the hub fails `locale_near_duplicate` (critical) when they are too close, and the job comes back through the translate queue as `rework` with its issues.
- Post with `lang`, `locale` and `keyword`. The hub refuses a non-source locale before approval with 409 `source_not_approved` — that is expected, not an error to retry.

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

- One primary keyword per article (from `topic.json.keyword`). It appears in: title, H1, the `introduction` field, at least one H2, meta description, and the **slug/URL** (as a contiguous keyword phrase — see Internal links and slugs). The old "first 100 words of the body" rule is gone — the hub checks the keyword against `introduction` (`intro_keyword`, critical), not the opening of `bodyMd`.
- The hub checks keyword placement as a contiguous phrase, ignoring punctuation and English function words (a, an, the, in, on, at, for, of, to, and, or, with, from, by, vs). So the keyword `hair transplant egypt uk patients` is satisfied by "Hair transplant in Egypt for UK patients" but not by "hair transplant for patients from the UK in Egypt". Topic-scout must choose keywords that read naturally as one phrase; writers must keep that word order wherever the keyword is required.
- The slug is derived once from the topic keyword, in English, and shared by every language version. A localized version's `keyword` is the native-language term used for title/H1/H2/meta/body placement only; it never changes the slug. If `topic.json.slug` is set (a pinned slug from the brief), use it verbatim as `draft.json.slug` for every language version — do not derive one from the keyword. The hub rejects any other slug with 400 `slug_pinned`. Keep primary-keyword density **at or under 4%** of the body words — the hub warns on `keyword_stuffing` above that; never awkward repetition.
- 3–6 secondary keywords from research (People Also Ask, competitor headings, autocomplete) used naturally in H2/H3s and body.
- Meta title 45–60 characters (Arabic: 39–70); aim 50–58 for English — the hub warns `title_length_aim` above 58. Meta description 130–155 characters, Arabic 110–180. Meta title ≠ H1 wording exactly; it may add a hook ("2026 guide", "costs & clinics").

### Keyword Planner volume (v2 phase 8)

- When `/api/plan` includes `keywordIdeas` for a site (`PROVIDER_KEYWORDS=keyword-planner`), topic-scout treats each market's `ideas[]` as the first source of candidates for that market, ahead of autocomplete and People Also Ask — "strong = real volume" (docs 02 §1). Prefer candidates with `avgMonthlySearches ≥ 50` for a bottom- or mid-funnel page; a candidate at 0–10 is allowed only when it is a help question or a long-tail constraint page and no ≥ 50 alternative fits the slot. Tier hint from volume: **≥ 5,000** → `broad` (homepage/category only — never a new blog post), **500–4,999** → `medium` (category/pillar/cost/procedure), **< 500** → `long` (blog/help/constraint). Record the volume in `topic.json.rationale`, e.g. `"KP volume 320/mo, SA/ar"`.
- Same-language, multi-market sites: when otherwise-similar candidates could serve more than one market, pick the market whose `keywordIdeas` list contains the seed with the highest `avgMonthlySearches`, and write the topic in that market's wording (Market rules already cover `glossary`/`currency`).
- When `keywordIdeas`/`keywordVolumes` are absent from the plan (provider `free`), none of the above applies — current behaviour (autocomplete/PAA ranking only) is unchanged.

### Commercial targets and SERP evidence

- `/api/plan` includes `recommendedTargets[]` from SEOhub's Next targets page. Candidates are ranked from operator-entered business value (1–5), manually entered trailing-90-day organic leads/revenue for the associated landing page, cached Keyword Planner volume and market priority. Outcomes are page-level context, not conversions attributed to the query. Missing conversion data is unknown, not zero business value. A recommendation never outranks an explicit human queue, a refresh, or an approved brief.
- For every shortlisted recommended keyword, topic-scout checks the current top search results in that country and language before it commits the topic. If the hub supplies a recent `serpResults[]` sample, use it; otherwise WebSearch the phrase. State the dominant page format and two real competing URLs in `topic.json.rationale`. Match the `pageType` to the actual search intent and the site's offer; reject a candidate where the proposed article cannot satisfy the results. A high vendor volume or difficulty estimate alone is insufficient.
- Competitor referring-domain overlap is a prospect-finding signal. The hub's outreach page stages it for human qualification and link verification; no outreach is sent automatically, and an absent domain in a provider sample is not proof that no link exists.

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
| the grouping level of any site's home → category → item tree: a procedure family or specialty ("hair transplant in Egypt", "dermatology treatments"), a tour category ("Nile cruises"), a course track ("endoscopy courses"), a product category ("fresh meat") | `category` (v2 phase 8) |
| a single offer at the item level on any site: a shop product, a clinic package or service, a course, a stay, a consulting service ("long navy blue bridesmaid dress", "FUE hair transplant package", "upper GI endoscopy course") — never a trip/tour (`tour`) and never a medical procedure page (`procedure`) | `product` (v2 phase 8) |
| a direct question a short, sourced answer settles ("is X safe", "do I need a visa for X") | `help` |
| broad/how-it-works background with no first-party data or decision aid | `guide` — use sparingly; the hub refuses a site's 4th `guide` job in a row while it is under its bottom-funnel quota (`400 guide_quota_exceeded` from `create-job` — see Keyword collisions) |

A `queuedTopics[]` row may already carry a `pageType` (an admin or the ledger set it) — never override that one; only assign `pageType` yourself for a topic-scout-discovered topic. Pass it straight through in `create-job`'s `topic` object; the hub uses it to pick that type's template and required-links checks (see `required_links_missing` etc. below) — a topic with no `pageType` simply skips those checks. (v2 phase 4) A brief-based job (`{"siteId","briefId"}`) carries its brief's `pageType` the same way — see Writer modes by page type below.

### Writer modes by page type (v2 phase 4)

Whichever way `pageType` got set — topic-scout, a queued-topic row, or a hub-approved brief — the writer follows that type's mode in addition to every other rule in this file:

- `procedure`, `cluster`, `guide`, `author`, `about`, `landing`, or no `pageType` at all: the base `write` procedure, unchanged.
- `cost`: a pricing table naming at least 2–3 concrete, real providers/clinics/options with currency and year, plus a short "what affects the price" section. Providers are named, not linked (Link policy).
- `comparison`: a markdown table comparing named, real competitors or options by the reader's actual decision criteria, with **at least one row where the site/subject honestly loses or ties** — a comparison with no losses reads as an ad, not research, and fails E-E-A-T trust. Never invent a competitor or a number for one. Name competitors without linking them (Link policy).
- `alternative`: 5–8 real alternative options (not fewer, not a wall of 20), each with a one-line "best for" and its own honest trade-off.
- `constraint`: written for a reader who may be ruled out by a specific constraint (budget, age, medical condition, timing) — lead with whether they qualify, then what to do if they don't.
- `help`: answer-first — the direct answer in the first sentence, no throat-clearing intro — matching the hub's `answer_first` help-center check.
- `tool`: write only the tool's copy (`methodologyMd`, `dataSource`, `asOf`, `faq[]`); never invent the calculator's logic/config, and never guess `dataSource`/`asOf` without a source in research.
- `pillar`: an overview that introduces and links every member of its hub (member titles/slugs come from the brief); no facts of its own beyond what is needed to summarize each member. The primary keyword appears in **at least 2 H2s** (doc 03 — more than the usual ≥ 1 H2 rule, because a pillar's sections are the member summaries themselves). `schemaJsonld` swaps `BlogPosting` for `CollectionPage` + `ItemList` of the members.
- `category` (v2 phase 8): H1 = keyword + appeal ("Shop Elegant Bridesmaid Dresses for Every Style and Season"); intro with the keyword and 1–2 natural variations; body ends with a "why us" section (reviews, policies, awards) then a longer content block (tips/care/FAQ). `schemaJsonld` swaps `BlogPosting` for `CollectionPage` + `ItemList`. Links the site's pillar page unless the job's `hubRole` is `pillar` — a category page that is itself the hub's pillar needs no separate pillar link, the same exception as the `pillar` type. A pinned-slug brief (`topic.json.slug` set) on a `category` job is a site page rendered outside the blog — the site owns the page chrome (price block, CTA, breadcrumbs), so `bodyMd` is the descriptive copy only: no title H1, no closing CTA paragraph beyond the site's own CTA sentence. Target 400–800 words (Structure rules).
- `tour`: a specific trip page. Base `write` procedure, with the same pinned-slug handling as `category`: when the brief pins `topic.json.slug`, the page is site-rendered outside the blog and owns its own price block/CTA/breadcrumbs, so `bodyMd` is descriptive copy only — no title H1, no closing CTA paragraph beyond the site's own CTA sentence. Target 800–1,400 words (Structure rules).
- `product` (v2 phase 8): H1 = the product/service name as the keyword ("Long Navy Blue Bridesmaid Dress"); ≥ 300 words covering what it is, who it's for, what's included/not, price with currency and an "as of" date, delivery/duration, care/recovery, FAQ. Never copy manufacturer/supplier text. Never use `product` for a trip or tour — that's the `tour` page type, always. Schema is vertical-dependent (doc 04): `schemaJsonld` swaps `BlogPosting` for `Product` + `Offer` (shop products, stays) or `Service` + `Offer` (clinic packages, services, and courses); the hub accepts **only** `Product` or `Service` for the type check, so a course page uses `Service` + `Offer` — never `Course`, which trips `template_schema_mismatch`. Links: the pillar (category), 2 related products (siblings), 1 money page (booking/contact).

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
- `references`: every research/government source URL (Link policy) you cited in `bodyMd` from `research.json.facts[]`, as `{ "title", "url", "publisher", "date" }`. `title` and `url` are required, `publisher` and `date` are filled when research has them. Medical sites need **at least 2**, every URL **https**, and every URL must also appear inline in `bodyMd`.
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
- **`keywordNotes`**: free text on how that market actually searches. Topic-scout reads it when phrasing and ranking candidate keywords for that market (see its own file). Which market a candidate should serve is decided by `marketPlan` (see Country priority and weekly targets below); only when `marketPlan` leaves it open — every row `needed: null`, i.e. the site set no targets — does it fall back to the old local round-robin across `site.markets`.
- **Localizer**, writing a `LANG` version rather than the job's own `market`: when `LANG` maps to exactly one entry in `site.markets`, that entry's `rules`/`glossary`/`currency`/`cta` apply. When `LANG` maps to several, the job's own `market` wins if that entry's `lang` is `LANG`; otherwise use the first `site.markets` entry whose `lang` is `LANG`.

Writer, localizer and auditor all read the job's market entry before writing or checking a word. A market with no `rules`/`glossary`/`cta` simply falls back to the site defaults for those fields — nothing extra to add.

## Country priority and weekly targets (hub contract 1.12.0)

A `site.markets[]` entry may also carry `priority` (1–5, 1 first) and `weeklyTarget` (articles per week for that market). Omar sets both on the hub's `/sites/:id` → **Next week's run** card, and `/api/plan` turns them into a per-site `marketPlan`, already in priority order:

```json
"marketPlan": [
  { "country": "SA", "lang": "ar", "priority": 1, "weeklyTarget": 3, "jobsThisWeek": 2, "needed": 1 },
  { "country": "GB", "lang": "en", "priority": 2, "weeklyTarget": 1, "jobsThisWeek": 1, "needed": 0 },
  { "country": "EG", "lang": "ar", "priority": null, "weeklyTarget": null, "jobsThisWeek": 0, "needed": null }
]
```

- **Fill in order.** Give this week's slots to the rows top to bottom, `needed` articles each, before any row further down gets one.
- **`needed: null` is not zero.** That market has no number of its own; it takes whatever the week has left, after every targeted row is satisfied. This is also what every market looks like on a site that never set targets — which is exactly the old behaviour, so `marketPlan` changes nothing until Omar fills it in.
- **`needed: 0`** means that market is done for the week; move down the list rather than adding another one there.
- **A rank never blocks a market.** Priority is an order, not a permission — an unranked market is still a legitimate place for an article once the ranked ones are satisfied.
- **`neededThisWeek` is the site's own total** and already accounts for this: it is the sum of the `weeklyTarget`s once any market sets one, and `cadencePerWeek` otherwise. Never create more than it says; `marketPlan` decides *where* those articles go, not *how many*.
- Publishing the same article in more than one language or for more than one country is not duplicate-content spam — Google's multi-regional guidance asks for hreflang, which the hub already writes. What its spam policies target is scaled content abuse: bulk translation that adds nothing. So a market that gets its own articles gets its own angle — that market's `rules`, `glossary`, `currency`, `cta` and `keywordNotes` are mandatory reading, per Market rules above.

## E-E-A-T and medical safety

- Byline is the site's `author` (name, credentials). Medical sites: include one sentence of "reviewed by {{site.reviewer.name}}, {{site.reviewer.credentials}}" in the closing section — the **reviewer**, not the author — and set `Person` schema. The hub fails `reviewer_present` (critical) when the site has no reviewer name or credentials, and `structured_data_valid` when `reviewedBy.name` does not match `site.reviewer.name` exactly.
- Medical content: describe procedures, risks, recovery honestly; recommend a consultation; never diagnose; never promise results; no "best", "painless", "100%".
- Cite at least 2 research or government sources (Link policy) from research, https only. Never cite a competitor, clinic, agency, blog or news site as a linked source.

## Internal links and slugs

- Slug — the slug **is** the URL path (`/blog/<lang>/<slug>`), so it is the keyword signal Google reads from the address bar; a keyword-bearing URL boosts visibility and a slug that drops the keyword wastes that signal. Rules: lowercase, ASCII, hyphens, ≤ 60 chars, and it **must contain the primary keyword as a contiguous phrase in the keyword's word order**, dropping only stop words and any trailing market/qualifier words that overflow 60 chars — the keyword words lead. **A non-Latin keyword is translated into English, never transliterated**: the slug for `زراعة الشعر في مصر` is `hair-transplant-egypt`, not `zeraat-el-shaar-fi-masr`. Franco-Arabic in the address bar reads as spam to a reader and carries no keyword signal in any language. The hub warns `slug_ascii` on a slug that still has non-Latin characters in it, and fails `slug_franco` on a Latin slug that is transliterated Arabic (`zeraat`, `fi`, `masr`, Arabizi digits like `3ilag`). Derive it from `topic.json.keyword`, never from a paraphrased title. All language versions share this one primary (ASCII) slug: a localized version's native `keyword` changes on-page text only, never the URL. If `topic.json.slug` is set (a pinned slug from the brief), use it verbatim as `draft.json.slug` for every language version — do not derive one from the keyword; the hub rejects any other slug with 400 `slug_pinned`. (A pinned slug is chosen by the brief author and should itself carry the keyword — that is the brief's responsibility, not the writer's.)
- Internal links: from `existingArticles` for the same site, prefer the same language; 2–4 links when the site has ≥ 2 articles, otherwise as many as exist (0 or 1). Link with descriptive anchor text inside a sentence, path `/blog/<lang>/<slug>`. Never link to the article itself.
- `draft.json.internalLinks` must list exactly what `bodyMd` links to. `internal_link_count` counts that field, not the markdown, and the hub's link graph is rebuilt from it — a link in the prose that is missing from the field is invisible to both. When an operator saves an article in the hub's editor, the hub re-derives the field from the body's site-relative links, so the two cannot drift after a hand edit; the writer still has to get it right when it posts the draft.

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

Deterministic (hub), critical: `keyword_title, keyword_h1, keyword_meta, meta_title_length, meta_description_length, h1_count, heading_skip, word_count, internal_link_count, internal_link_missing, competitor_link, locale_keyword_missing, locale_near_duplicate, external_http, faq_count, title_duplicate, banned_phrase, thin_content, intro_keyword, image_alt, structured_data_valid, near_duplicate_site`; also `slug_franco` on a draft whose slug is not already live.
Deterministic (hub), warning: `keyword_h2, paragraph_length, keyword_stuffing, meta_description_duplicate, intro_length, secondary_keywords_used, og_fields, hreflang_reciprocal, cta_present, near_duplicate_portfolio, title_length_aim, intro_pillar_link, bold_per_paragraph, caption_missing, glossary_term_ignored, currency_mismatch, slug_ascii`.
`slug_ascii` — the slug still has non-Latin characters in it, so it was never translated (see Internal links and slugs). Rewrite it as the English wording of the keyword; every language version then shares that one slug. A warning rather than a critical so an article already published under a non-Latin slug stays publishable — changing a live slug breaks every inbound link to it.
`slug_franco` (hub contract 1.14.0) — the slug is Latin but the words are transliterated Arabic (franco-Arabic): a known transliteration such as `zeraat`, `shaar`, `fi`, `masr`, `se3r`, or an Arabizi digit standing in for a letter (`3ilag`, `ta7t`). Replace it with the English translation of the keyword — `hair-transplant-egypt`, not `zeraat-el-shaar-fi-masr`. Critical on a draft (the audit loop must fix it before posting); a warning at publish time and when the slug is already live (a refresh keeps its slug byte-identical), so a published article is never blocked by it.
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

A keyword another of our own sites already owns is **no longer refused** (hub contract 1.11.0): `create-job` creates the job and, when a *different* site owns that (normalized keyword, language), the response carries a non-blocking `sharedWith: {"ownerSiteId","ownerSiteSlug","targetUrl"}` and the hub records the overlap as a `planned` ledger row. Nothing to handle — do not drop the topic; note the owning site in the run summary so the overlap is visible. Discovery still steers clear by default: `/api/plan`'s `blockedTopics[]` lists those keywords in advance, and topic-scout drops any candidate matching one before spending a search on it, so an overlap should only ever come from a topic Omar queued or briefed deliberately.

`create-job` also returns **HTTP 400** with `{"error":"guide_quota_exceeded"}` when the site has had 3 consecutive `guide` jobs and is under its bottom-funnel quota (`sites.mixTargets.bottom`). Drop that topic's `pageType` down to something bottom-funnel-shaped (`cost`, `procedure`/`tour`, `help`, `tool`) if the keyword supports it, or pick the next topic — never retry the same `pageType` for that slot.

## Refresh jobs

The hub queues a topic with `"source": "refresh"` and `"refreshJobId": <job id>` when a published article reaches `planned_update_at` (`published_at + site.refreshMonths`). A refresh topic is exempt from the keyword guard on purpose — the job re-uses the original keyword and slug and republishes through `adapter.update`. When a queued topic has `source: "refresh"`, create the job with `{"siteId", "topicId", "refreshOf": <topic.refreshJobId>}` and dispatch the writer with `MODE=refresh`: it fetches the published article with `scripts/hub.sh articles <JOB_ID> <FILE>` and revises that article against the research — updated facts, dates, references and safety sections — instead of writing a new one. `slug` stays byte-identical to the published article: the hub carries `remoteId`/`remoteUrl` over from the original job so the receiver updates the live post, and a changed slug would create a second post and break every internal link pointing at the old one.

## Forced topics

`/api/plan` carries a queued topic Omar ticked "force this idea next run" in `forcedTopics[]` instead of `queuedTopics[]` (the two are disjoint — every `topics` row is in exactly one). The orchestrator gives every `forcedTopics[]` entry a job unconditionally, even when the site's `neededThisWeek` is already 0 — a forced idea is not subject to cadence (SKILL.md §1). Otherwise it is handled exactly like a queued topic: same fields (`id, title, keyword, market, lang, source, pageType, brief`), same `topicId` job-create path, and a non-empty `brief` makes it a refine job the same way.

## Refine jobs

A `queuedTopics[]` or `forcedTopics[]` row may carry `brief` — Omar's own idea or rough draft for the article, meant as the article's backbone rather than a topic to research from scratch. When it is a non-empty string, the orchestrator copies it verbatim into `topic.json` and dispatches the writer with `MODE=refine` instead of `write` (SKILL.md §3; `refresh` wins if a job somehow has both `refreshOf` and a `brief`, which should never happen since forced/queued topics and the refresh queue are separate sources). The writer procedure is the same as `write` — full research grounding, the same self-check, the same `scripts/hub.sh audit` — except the brief supplies the starting structure and claims instead of a blank page; see `.claude/agents/writer.md` → Procedure — `refine`.

## Ledger ownership and optimize-first

`/api/plan` also carries, per site: `ownedTopics` (this site's own `owned` rows in the topic ledger — `{ "normalizedKey", "language", "targetUrl" }`) and `optimizePreferred` (existing pages GSC evidence says to refresh rather than compete with a new draft — `{ "jobId", "slug", "lang", "query", "position" }`).

- **`ownedTopics`**: a keyword this site has already claimed, whether or not it has a published article yet. Topic-scout adopts any entry not already covered by `existingArticles`/`queuedTopics` before it spends a single search — see its own file, step 0. There is no collision risk (the ledger already says this site owns it), so it always beats a discovered candidate for the same slot.
- **`optimizePreferred`**: a *published* page whose own keyword is showing up at striking distance in Search Console. Refreshing it is cheaper and more likely to move the needle than a new page competing for the same intent. The orchestrator creates the refresh job directly from the entry (`refreshOf: entry.jobId`, `topic.source: "refresh"` — see SKILL.md §1) instead of asking topic-scout to discover that query; topic-scout drops any candidate matching one so the same query never becomes two jobs.
