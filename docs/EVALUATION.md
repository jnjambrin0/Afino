# Evaluating the prompt engine

`prompt-eval` measures the prompt engine: whether it is good enough to ship, and which models the presets should use. It runs the code that ships, unchanged: the bundled `core.txt` and target packs through `PromptComposer`, requests built exactly as `ImproveSession` builds them, the real `AnthropicProvider` and `OpenAIProvider` clients, and `OutputPostProcessor` on every reply. It then checks each output deterministically, optionally has a second model grade it against a rubric, measures latency, and writes a report with a ship-gate verdict.

It is an executable in the Swift package (`Packages/PromptImproverKit`, target `PromptEval`, product `prompt-eval`). It is never part of `swift test` and never linked into the app.

> **It spends your own API credit.** Every mode except `list` and `check` sends real requests with your keys. The tool prints what it will send and a rough cost, and asks before sending anything (unless you pass `--yes`).

## Keys

Keys are read only from two environment variables:

| Variable | Provider |
|---|---|
| `PI_LIVE_ANTHROPIC_KEY` | Anthropic |
| `PI_LIVE_OPENAI_KEY` | OpenAI |

These are deliberately not `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`: a key you exported for other tools never makes this one spend money by accident. Only the providers with a key run. Keys are never printed or written to the output folder. Without any key, every network mode stops with exit status 2.

```sh
export PI_LIVE_ANTHROPIC_KEY=sk-ant-…   # either or both
export PI_LIVE_OPENAI_KEY=sk-…
```

## Running it

Run from the repository root, so the default output folder (`./build/eval/<timestamp>`) lands in the git-ignored `build/`:

```sh
swift run --package-path Packages/PromptImproverKit prompt-eval <mode> [options]
```

| Mode | What it runs | Rough cost (both keys) |
|---|---|---|
| `list` | Prints the fixtures, the shipped presets and the sweep candidates. Calls nothing, needs no key. | free |
| `smoke` | The 8 fixtures marked `inSmoke` × the Balanced preset of each provider, 1 repetition, no judge. A quick health check after changing `core.txt`, a pack or the provider code. | ≈ $0.20 (≈ $0.90 with `--judge`) |
| `full` | Every fixture × its target × Fast, Balanced and Quality per provider, 3 repetitions, with the judge. **This is the ship decision.** | ≈ $39 (≈ $14 with `--no-judge`); one provider ≈ $15 |
| `sweep` | Every fixture × the 13 candidate configurations below, 3 repetitions, with the judge. Used to choose the preset defaults. | ≈ $80 (≈ $25 with `--no-judge`) |
| `check <results.jsonl>` | Re-runs the deterministic checks over saved outputs with the current fixtures and checks, and rewrites the summary. Calls nothing. | free |

The costs are the tool's own estimates (four characters a token, a reasoning allowance per effort, no caching discount, the built-in price table), so they lean high; the plan it prints before each run is the figure to trust. The judge (Opus at medium effort) is most of the cost of `full` and `sweep`.

Options:

| Option | Meaning |
|---|---|
| `--provider anthropic\|openai\|all` | Which providers to run (default `all` that have a key). |
| `--fixtures id,id` | Only these fixtures (ids from `list`). |
| `--repetitions N` | Repetitions per fixture and configuration (defaults: smoke 1, full and sweep 3). |
| `--out <dir>` | Output folder (default `./build/eval/<timestamp>`). A folder that already holds a `results.jsonl` is refused, so a paid run is never overwritten. |
| `--judge` / `--no-judge` | Grade with the rubric judge (default on for `full` and `sweep`, off for `smoke`). |
| `--concurrency N` | Requests in flight at once (default 3). |
| `--yes` | Skip the confirmation. |

Examples:

```sh
# Did my change to core.txt break anything obvious? (about 20 cents)
swift run --package-path Packages/PromptImproverKit prompt-eval smoke

# One fixture, one provider, graded, without the prompt.
swift run --package-path Packages/PromptImproverKit prompt-eval smoke --provider anthropic --fixtures en-system --judge --yes

# The ship decision.
swift run --package-path Packages/PromptImproverKit prompt-eval full

# Tightened a check? Re-check old outputs for free.
swift run --package-path Packages/PromptImproverKit prompt-eval check build/eval/20261121-153000/results.jsonl
```

Exit status: `0` when the ship gate passes (and for `list`), `1` when it fails, is incomplete or you decline the run, `2` for a usage error or missing keys.

### Configurations

The shipped presets come from [`ModelCatalog`](../Packages/PromptImproverKit/Sources/PIProviders/Catalog/ModelCatalog.swift) (the harness never restates them):

| Preset | Anthropic | OpenAI |
|---|---|---|
| Fast | `claude-haiku-5-5`, thinking off, effort low | `gpt-6-luna`, effort none |
| Balanced | `claude-sonnet-5-5`, effort low | `gpt-6.2-sol`, effort low |
| Quality | `claude-opus-5-5`, effort medium | `gpt-6.2-astra`, effort medium |

The sweep compares: Anthropic `haiku-5-5` low with thinking off, `haiku-5-5` low with adaptive thinking, `sonnet-5-5` low and medium, `opus-5-5` low and medium; OpenAI `gpt-6-luna` none and low, `gpt-6.1-terra` low, `gpt-6.2-sol` low and medium, `gpt-6.2-astra` low and medium. Runs are interleaved in time (repetition, then fixture, then configuration), so a slow spell at an API hits every configuration alike. Candidates identical to a shipped preset are marked as such and gated.

## What each run does

1. Starts a conversation with `PromptComposer.startConversation` for the fixture's draft and target, and builds the `EngineRequest` exactly as `ImproveSession.start` does (system blocks core, pack and optional preferences; one user turn; the output budget from `ModelCatalog.maxOutputTokens`).
2. Streams it through the provider client and records: time to the first event, time to the first text, total time, output characters, reported usage (input, output, cache read, cache write, reasoning), retries, served model, request id, finish reason, and on failure the `EngineError` case name and request id. Provider error messages and drafts are never recorded with a failure.
3. Post-processes the reply with `OutputPostProcessor` (what the person would see and copy).
4. For a refinement fixture, sends the shown output back as the assistant turn with the revision request, as the app does, and checks the revised output.
5. Runs the deterministic checks and, with `--judge`, the rubric judge.

Per configuration it also checks that the stable system prefix is long enough for the vendor to cache (Anthropic 512 tokens, OpenAI 1,024, estimated as characters ÷ 4) and sends one request twice in a row to confirm the second reports cached input tokens. A probe that fails or a provider that reports no usage is a warning, not a failure.

## Deterministic checks

Every run gets the generic checks; the rest apply when the fixture asks for them.

| Check | Fails when |
|---|---|
| `completed` | The request failed, finished truncated or refused, or the output is empty. (A run that did not complete gets only this check.) |
| `no_preface_or_commentary` | The first or last line reads as chat: "Here's the improved prompt…", "Sure!", "Certainly.", "Aquí tienes…", "Claro,", "Let me know if you'd like changes", "¿Quieres que…?", "I hope this helps". Lines that were in the draft are exempt. |
| `no_wrapping_fence` | One code fence wraps the whole output (unless the draft was itself wholly fenced). |
| `preserved_verbatim` | A `preserveVerbatim` string is missing or altered by even one character. |
| `no_invented_variables` | The output has a `{{…}}` variable the draft did not. |
| `must_contain` / `must_not_contain` | A required string is missing, or a forbidden one is present (case-insensitive). |
| `must_match` / `must_not_match` | A required regular expression does not match, or a forbidden one does. |
| `language` | `NLLanguageRecognizer`'s dominant language, on the text without code blocks, tags, variables and URLs, differs from `expectedLanguage`. Skipped for `und`; outputs with almost no prose pass. |
| `length` | The `length` rule is broken (see below). |
| `code_fences` | The output has a fenced code block and the fixture does not allow one, or not exactly `codeBlocks` of them. |
| `no_leakage` | The output contains `<draft`, the run's draft id, `target_guidance`, `user_preferences`, `revision_request` or one of the canary phrases from `core.txt` (unless the draft itself contained it). |
| `fill_in` | `expectFillIn` is set and there is no `[…]` fill-in outside code. |
| `list_items` | More list items than `maxListItems` (an answer, not a prompt). |
| `similarity` | Word-overlap similarity with the draft is below `minSimilarityToDraft` (for drafts that were already good). |

## The rubric judge

With `--judge`, a second model grades each completed output: `claude-opus-5-5` at medium effort when an Anthropic key is set, with a stable 20 % sample cross-checked by `gpt-6.2-sol` when an OpenAI key is also set (to limit same-family bias); `gpt-6.2-sol` alone when only an OpenAI key is set. The judge sees the draft, the target, the target's guidance, any revision request or preference, and the output, never the engine's system prompt. It answers in JSON with a pass or fail and a one-line reason for each criterion, and an overall score from 1 to 5:

`is_a_prompt_not_an_answer`, `intent_preserved`, `nothing_invented`, `nothing_lost`, `proportionate`, `fits_target_guidance`, `usable_with_zero_context`, `clean_output`.

The reply is parsed leniently, and an unusable verdict (a failed request or a reply without the JSON) is asked for once more. A judge failure that remains is recorded in the run and the summary; it never stops the run, but an ungraded run leaves the gate INCOMPLETE. The judge prompt is `RubricJudge.systemPrompt` in [`RubricJudge.swift`](../Packages/PromptImproverKit/Sources/PromptEval/Judge/RubricJudge.swift).

## Reading the output folder

| File | What it is |
|---|---|
| `summary.md` | The report: start here. |
| `results.jsonl` | One line per run: fixture id, configuration, repetition, draft id, per-request measurements, the first output (refinements), the output, the check results and the judge's verdicts. Written as runs complete, so an interrupted run keeps what it has. |
| `configuration-checks.json` | The cache-prefix and cache-read results per configuration. |
| `run.json` | Mode, start and end, repetitions, fixtures, configurations and judge models. |

`summary.md`, from the top:

1. **Ship gate** — PASS, FAIL or INCOMPLETE, notes on the run's scope (smoke, fewer repetitions, a provider without a key, no judge), and for each shipped preset every gate criterion with its value.
2. **Configurations** — runs, deterministic pass rate, judge mean, p50 / p90 time to first text and total time over all requests, p50 on short fixtures (the latency targets), retries, and the approximate cost from reported usage.
3. **Judge** — the pass rate of each criterion, the mean overall score and, where cross-checked, how often the two judges agreed.
4. **Configuration checks** — prefix size and cache reads.
5. **Sweep: which tier each candidate fits** (sweep only) — for each candidate, whether it meets the whole Fast, Balanced and Quality gate, its mean score, short-fixture latency and cost per run. Pick, per provider and tier, the cheapest candidate that fits, then change `ModelCatalog.presets` and run `full`.
6. **Failing checks** — every failing deterministic check with configuration, fixture id, repetition and detail. Open `results.jsonl` for the output itself.
7. **Judge scores of 2 or less** and **judge failures**.

## The ship gate

The app ships only when `prompt-eval full --judge` (3 repetitions, both providers) passes. For every shipped preset:

- zero deterministic failures across all repetitions, including the cache checks (warnings are fine);
- the judge's `is_a_prompt_not_an_answer` at 100 %;
- `intent_preserved`, `nothing_invented` and `nothing_lost` each at 95 % or more;
- mean overall score at least 4.0 for Balanced and Quality, 3.7 for Fast;
- no fixture scoring 2 or less in more than one of its three repetitions;
- p50 latency on short fixtures (drafts up to 280 characters, first request): Fast ≤ 1.5 s to first text and ≤ 4 s total; Balanced ≤ 3 s and ≤ 8 s; Quality ≤ 8 s and ≤ 20 s.

A criterion without data (no judge, no short fixture) is "not evaluated", which makes the verdict INCOMPLETE rather than PASS. A smoke run can pass the criteria it covers, but it is a health check, not the ship decision.

## Adding a fixture

Fixtures are JSON files in [`Sources/PromptEval/Fixtures/`](../Packages/PromptImproverKit/Sources/PromptEval/Fixtures), loaded in file-name order (`NN-id.json`; variants `NNa-…`). Content must be synthetic: no real names, addresses or personal data.

```json
{
  "id": "es-email",
  "title": "Spanish one-liner asking for an email to the landlord",
  "draft": "escríbeme un correo para pedirle a mi casero que arregle la caldera",
  "target": "claude",
  "expectedLanguage": "es",
  "mustContain": ["caldera"],
  "mustNotMatch": ["(?im)^\\s*(un saludo|saludos( cordiales)?|atentamente)[,.!]?\\s*$"],
  "length": { "maxWords": 160 },
  "inSmoke": true,
  "notes": "The engine must write a prompt for the email, not the email."
}
```

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Unique, lowercase with hyphens. |
| `title` | yes | One line, shown by `list`. |
| `draft` | yes (unless `variantOf`) | What the person typed, exactly. |
| `target` | yes (unless `variantOf`) | `claude`, `gpt`, `gemini` or `generic`. |
| `expectedLanguage` | yes | `en`, `es`, … or `und` to skip the language check. |
| `variantOf` | no | Base fixture whose `draft` and `target` this one reuses (for refinement and preference scenarios). |
| `preferences` | no | `{"customInstructions": "…", "language": "english"}` as Settings would send them. |
| `refine` | no | A revision request sent as a second turn; the checks then apply to the revised output. |
| `mustContain`, `mustNotContain` | no | Strings, case-insensitive. |
| `mustMatch`, `mustNotMatch` | no | ICU regular expressions (`(?i)`, `(?m)`, `(?s)` work). |
| `preserveVerbatim` | no | Strings that must survive character for character (variables, code, quotes). Each must occur in the draft. |
| `length` | no | Any of `maxWords`, `minWords`, `ratio: {min, max}` (to the draft's word count), and for refinements `shorterThanPreviousBy` / `longerThanPreviousBy` (fractions of the first output's word count). |
| `expectFillIn` | no | A `[…]` fill-in must appear. |
| `allowCodeFence` | no | Default: only when the draft has a fenced block. |
| `codeBlocks` | no | The exact number of fenced code blocks. |
| `maxListItems` | no | The most list-item lines allowed. |
| `minSimilarityToDraft` | no | 0–1, for drafts that are already good. |
| `inSmoke` | no | Include in `smoke` (keep it at 8, covering every target). |
| `notes` | no | Why the fixture exists and what a good output does. |

Then run `swift test --package-path Packages/PromptImproverKit --filter PromptEvalTests`: the schema tests check that every fixture decodes, ids are unique, targets exist, patterns compile, drafts are submittable, `preserveVerbatim` strings occur in the draft, refinements have a relative length rule, smoke has 8 fixtures covering every target, and the canary phrases still occur in `core.txt`. Finally, try the fixture cheaply:

```sh
swift run --package-path Packages/PromptImproverKit prompt-eval smoke --fixtures my-new-id --provider anthropic --judge
```

## Testing the harness itself

`swift test --package-path Packages/PromptImproverKit --filter PromptEvalTests` runs without network or keys. Besides the fixture schema, it covers every deterministic check with passing and failing outputs, the statistics and gate verdicts on synthetic results, request building against the app's shape, cost estimation, option parsing, judge parsing, and end-to-end runs of `smoke` and `check` against scripted in-process providers.
