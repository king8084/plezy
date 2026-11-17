# Smart search: research and bounded pilot

Research date: November 16, 2026. Source reviewed: 6f2026663 on
codex/first-tvos-test-build. The initial research did not access servers or alter
the application. The owner subsequently authorized a tiny connectivity check and
then a metadata-only, one-season indexing pilot. Measured pilot results appear
below; no search service or Apple TV integration has been deployed.

## Product intent

Provide fast ordinary search with optional conceptual/scene search through a
locally hosted Ollama service. Return owned items with their existing library
identity and artwork; show verified requestable discoveries separately through
the existing Seerr flow. Preserve the approved Home/detail layouts and remote
focus behavior. Latest owner direction: consider automatic parallel result paths
instead of the earlier AI checkbox proposal. This remains a product proposal;
the pilot does not change Search or its current controls.

- Return ordinary indexed title, person, genre and stored-text matches first,
  without waiting for Ollama. A text match does not prove a remembered scene.
- Run conceptual search in a separate AI row after settled input or submission;
  avoid generation for every remote keystroke. Query embeddings can be quick
  while evidence checking or a cold reasoning-model load takes longer.
- Append AI results/loading state without moving focus, reordering ordinary
  results, clearing them, or changing the approved Home/detail layouts.
- Keep the fast path usable when the inference PC is asleep. Explain AI
  unavailability within its row rather than holding the whole search screen.
- Retain query-generation and profile/scope guards; ignore obsolete responses
  and propagate cancellation where supported. Ignoring output does not prove
  that remote inference stopped. Use scoped caches and idle expiry.
- Connect only to configured services/models. Search must not start containers,
  pull models, alter global Ollama configuration, or unload another user's model.
- Distinguish retrieved candidates from answers backed by synopsis evidence.
  Nearest-neighbor similarity alone cannot establish a supported match.

A novel conceptual query still needs an embedding or other interpretation at
query time even when document embeddings were generated in advance. Cached
verified results can be reused only with matching scope and evidence revision.

## What the current fork actually does

The shared DebouncedMediaSearch mixin waits 500 ms after a text change. SearchScreen
then calls DataAggregationService.searchAcrossServers; this is server search,
not a persistent full-library semantic index. Generation guards and aborts already
protect against obsolete responses. Hidden-library/profile filtering is present.
Do not globally shorten this shared debounce and increase traffic in every search
screen: measure a dedicated indexed path and retain fallback behavior separately.

Reusable integration points:

- lib/mixins/debounced_media_search.dart and lib/screens/search_screen.dart:
  input, submit, stale-response protection, kind/person filters and focus.
- lib/services/library_events/media_browser_library_event_socket.dart:
  Jellyfin LibraryChanged handling, keepalive and reconnect plumbing.
- lib/services/catalog/catalog_library_matcher.dart:
  profile-scoped external-ID/library matching; incomplete checks are not absence.
- lib/services/catalog/detail_recommendations.dart:
  owned/requested/missing/unknown states and existing Seerr navigation.
- Existing community ratings enrichment: reuse IMDb score/vote handling after
  results are shown, without holding the first result for enrichment.

## Confirmed capabilities and limits

Neptune documents a local metadata index, a separately curated semantic tag
catalog, and AI fallback for conceptual searches. Episode Finder includes uncertain
answers. Its public documentation does not disclose its full prompts, training
data, retrieval corpus, or ranking implementation. Its reported metadata indexing
rate is not an embedding or video-analysis benchmark for this project.
Sources: [local index](https://docs.neptuneplayer.com/search/local-index),
[semantic catalog](https://docs.neptuneplayer.com/search/semantic-search),
[AI Search](https://docs.neptuneplayer.com/search/prompt-search),
[Episode Finder](https://docs.neptuneplayer.com/neptune-ai/episode-finder).

Ollama supports model preloading and per-request residency controls. Memory pressure
can queue requests and cause model replacement; a warm-setting request is not a
guarantee of simultaneous residency. It reports loaded models, and its embedding
API accepts text batches and reports load/total durations. Structured output makes
responses machine-readable; it does not prove the model's factual answer correct.
Sources: [FAQ](https://docs.ollama.com/faq),
[loaded models](https://docs.ollama.com/api/ps),
[embedding API](https://docs.ollama.com/api/embed),
[structured outputs](https://docs.ollama.com/capabilities/structured-outputs).

Jellyfin exposes item metadata and library-change sets for additions, updates and
removals. API requests support paging and user scoping. The installed server's
version and restricted-account policy were subsequently checked in the tiny
probe; actual event delivery/reconciliation remains untested.
Sources: [item metadata](https://typescript-sdk.jellyfin.org/interfaces/generated-client.BaseItemDto.html),
[change sets](https://typescript-sdk.jellyfin.org/interfaces/generated-client.LibraryUpdateInfo.html),
[paged requests](https://kotlin-sdk.jellyfin.org/dokka/jellyfin-model/org.jellyfin.sdk.model.api.request/-get-items-request/index.html).

SQLite FTS5 supplies full-text, prefix indexing and ranking suitable for an initial
metadata-search prototype. It does not by itself supply the complete desired
typo handling or a semantic vector index. Choose/benchmark those components
separately instead of adding a vector server before measuring the workload.
Source: [FTS5](https://www.sqlite.org/fts5.html).

TMDB supports title search, external-ID resolution and keyword-based discovery.
Current Seerr develop source forwards keyword filters for movie/TV discovery;
the household's deployed version has not been inspected. The existing Plezy
Seerr wrapper currently uses title search and page-based discovery, so richer
discovery needs additional adapter work and version checks. A title's existence
does not verify a claimed scene. Sources:
[TMDB lookup](https://developer.themoviedb.org/docs/finding-data),
[TV discovery](https://developer.themoviedb.org/reference/discover-tv),
[keyword lookup](https://developer.themoviedb.org/reference/search-keyword),
[Seerr routes](https://github.com/seerr-team/seerr/blob/develop/server/routes/discover.ts).

## Service and storage proposal

Use a separate service with its own persistent appdata volume alongside Jellyfin,
not a modification of Jellyfin's managed database. Jellyfin supplies metadata
through its API; Ollama supplies inference. The service owns its metadata cache,
text index, versioned document embeddings, sync checkpoints and evaluation data.
Apple TV sends queries and renders familiar cards. No direct video-file access is
needed for this scope. Endpoint addresses and credentials belong in private config.

Owner's standing rule: never edit, delete, replace, rename or move existing video
or Jellyfin-managed files. Isolated Plezy-owned index/database additions are
permitted only inside the owner's dedicated smartsearch directory, whose exact
server/mount paths are recorded in the private ignored scope file. This does not
authorize container or server-setting changes. Credentials remain private.

The approved client mount is a network filesystem. Build and close the pilot
SQLite database locally, then copy a new immutable snapshot into a unique child
directory; verify it read-only without creating journals on the mount. A permanent
writer should run on storage local to its owning server process, not as a live
writable SQLite connection over NFS/SMB. See SQLite's
[network filesystem guidance](https://www.sqlite.org/useovernet.html).

Index each movie, show and episode separately. Preserve server/library/item IDs,
series/season/episode identity, aliases, language, descriptions and external IDs.
Technical fields can be recorded if needed; adding format-filter UI is not part
of this research scope. Do not concatenate a whole series into a truncated model
input. Long additional texts would need bounded, attributable chunks.

Every response and cache must enforce the active user's server permissions,
profile and hidden-library scope, including people/episode hits and counts. Shared
storage is not authorization to reveal the administrator's entire catalog. Resolve
how authorization refreshes and revocations work before exposing the service.
Recheck playback/request availability at action time. An unreachable server yields
unknown availability rather than a false Need request claim.

## Initial indexing and updates

Separate two stages so the owner gets useful search before AI preparation ends:

1. Import metadata in bounded API pages; populate ordinary text search as pages
   commit. Store checkpoints and coalesce library events during the import.
2. Generate document embeddings in bounded, low-priority batches. Store a hash of
   the actual embedding text plus model digest, dimensions and preprocessing
   version. Only changed inputs need embedding work. Changes to playback progress
   or favorites alone do not regenerate descriptive embeddings.

Keep the model version consistent between document and query embeddings. A model
change requires a separate embedding generation; do not mix incompatible vectors
or destroy the working search index. Resume interrupted work and make repeated
item updates idempotent. Paging a changing library requires reconciliation, not
an assumption that an offset checkpoint alone is a consistent snapshot.

After Jellyfin detects/imports an item, use its library event to queue the item
for an upsert or removal from the search index. Read metadata again after updates;
initial imports may have sparse descriptions. Include reconnect reconciliation
and a periodic inventory sweep to catch missed events, removals and permission
changes. Do not mark entries removed after a partial or failed inventory.

Show separate metadata and AI coverage progress, not a fabricated combined
percentage. Provide pause/resume and a clear partial-coverage state. Background
embedding should yield to interactive requests and be measured alongside playback
and other GPU workloads. No transcription, whole-video analysis, full-library LLM
tag generation, or bulk external synopsis scraping in the initial scope.

## Query paths and model readiness

Ordinary lookup should return a bounded ranked result set from the text index;
its latency must include remote-keyboard debounce, LAN transport, authorization
and rendering. Test on the actual Apple TV. A server index still needs the LAN;
fully offline instant lookup would require a separately designed client replica.

AI-enabled queries first retrieve relevant metadata using text/tags and a query
embedding, then use a bounded candidate shortlist for reasoning when needed.
For a known series, search that series' episode inventory before widening scope.
Cache verified results with query/scope/language, evidence/index revision and model
identity; retain evidence provenance and confidence. Keep direct title matches
ahead of loose conceptual candidates. Retrieval cannot manufacture facts absent
from its inputs. New or obscure episode scenes need adequate evidence or an
honestly uncertain answer; a model's confidence number is not calibrated proof.

External candidates require separate discovery and ID resolution. Do not index all
of TMDB or pass a plot sentence unchanged to a title-search endpoint and expect
semantic discovery. Verify relevance independently of whether a title exists.
Never let catalog calls, artwork, IMDb enrichment or LLM work hold local results.
The existing Seerr permission and explicit request action remain authoritative.

## Evaluation required before a full index

These are gates before a full index; the one-season pilot below does not satisfy
the representative-corpus, synchronization, authorization or device gates:

1. The owner supplied library counts and Ollama-host hardware on November 16;
   retain these household details in the private ignored inventory, not this
   public-repository note. Verify actual model/version, discrete-GPU use, spare
   memory, index-host SSD space, languages and Jellyfin/Seerr versions during the
   authorized pilot. Do not inspect Unraid using expired build permissions.
2. Define a representative query set and owner-verified answers: exact/partial
   titles, people, misspellings, plane-crash shows with aviation-only negatives,
   scene fragments such as Joey/chair, ambiguous memories, anime numbering,
   recent/obscure titles, unavailable servers and forbidden libraries.
3. Once separately authorized, run a bounded sample of metadata, approximately
   100-500 representative records spanning long and short episode descriptions.
   Measure metadata pages/sec and embedding throughput separately. Estimate the
   full job from the actual item/text distribution; report ranges, not a false
   exact time or Neptune's 4,000-record rate. No full index before this result.
4. Compare text/tag-only retrieval, embeddings, and optional reasoning for both
   precision and recall. Model selection remains open until this evidence exists.
5. Measure cold load, warm query embedding, retrieval, reasoning, availability
   lookup, first visible result and complete results. Record p50/p95, memory and
   the effect of concurrent indexing/playback. Provisional ordinary-search target
   is p95 at most 200 ms from settled input to initial usable results on the LAN;
   semantic/AI latency is unmeasured, not guaranteed subsecond.
6. Demonstrate restart/resume, event loss/reconnect, metadata edits, removal,
   interrupted inventories, model change, request permission failures and query/
   profile changes. No stale answers or cross-profile cache leaks.
7. Review the measured report and a small TV interaction prototype before a full
   index or app integration. Keep changes isolated and feature-controlled; rerun
   existing Home/detail/focus regressions and the required release gates before
   any explicitly requested Apple TV build.

Open decisions after research: corpus coverage, final model choice, vector backend
at full scale, readiness timeout/residency policy, permission enforcement and
final automatic-row interaction. The pilot adds an isolated experimental SQLite
schema only. There is no deployed service/container, application search change,
representative whole-library benchmark, install or device validation.

## Separate index and inference hosts

The owner intends Ollama to run on the everyday PC while the persistent search
service/index lives on Unraid. Ordinary indexed search must remain available when
that PC is asleep or unavailable. AI readiness then shows Unavailable rather than
holding or clearing ordinary results. The PC must be awake and reachable for new
inference. Account for shared gaming/desktop GPU use and actual free VRAM when
testing residency; total RAM is not the current memory budget.

Ollama's current Linux support list includes RX 9070 XT, but documentation is not
proof of acceleration in the household's installed runtime. Verify the actual
backend and GPU residency before attributing measurements to GPU inference. Do
not change drivers, GPU-selection settings, or running services as part of an
unapproved repair. Source: [Ollama GPU support](https://docs.ollama.com/gpu).

## Subsequent tiny connection check

The owner subsequently filled the private access file and requested only a very
small confirmation test. The restricted Jellyfin account authenticated with
administration and media deletion disabled. Three Movie/Series records exposed
descriptions and provider IDs. The first metadata request using only a legacy
token header returned 401; the SDK-style Authorization header and current Items
route succeeded without server changes. One installed local model returned a
two-token reply, with GPU residency reported by Ollama. Model loading dominated
the cold request. No installed embedding model was available.

The receipt stays private and Git-ignored. That connectivity-only step did not
download models, index episodes or evaluate retrieval. Do not extrapolate a
trivial reply into scene-search latency or a full-library indexing estimate.

## Authorized Modern Family season 4 pilot

The owner then explicitly authorized a real one-season test and designated a
dedicated smartsearch folder as the only server write location. The isolated
standard-library harness reads Jellyfin metadata, works locally, and exports
new files only into a uniquely named child of that approved folder. Existing
media and Jellyfin-managed files were untouched. No subtitle/video reads,
refresh operations, service/container deployment, full index or app build.

- Retrieved all 24 season-4 episodes with nonempty overviews; validated series,
  season and unique episode numbers. Season API request: 78 ms.
- Added the local `embeddinggemma:300m` model to the owner's Ollama installation
  for this pilot (621,875,917 bytes, about 622 MB). Existing models were retained.
  Model digest is recorded privately; query/document prefixes follow the
  [official model card](https://huggingface.co/google/embeddinggemma-300m) and
  [Ollama model entry](https://ollama.com/library/embeddinggemma).
- Four batches of six produced 768-dimensional normalized vectors. Document
  embedding requests totaled 1.889 s, including the first embedding-model load
  but excluding download/database writes. The model downloaded in about 13 s.
- Closed SQLite FTS5/vector snapshot: 172,032 bytes. Local integrity and exported
  read-only integrity/count checks passed. Exported files were checked against
  their source bytes and SHA-256 hashes; the manifest and harness are preserved.
- Thirteen positive queries selected from the owner's synopsis examples found
  the expected episode first in 13/13 semantic searches. The simple text baseline
  found the expected episode first in 11/13. This is a small preselected set,
  not an independent accuracy estimate; no ranking was tuned after evaluation.
- Median local text lookup: 0.107 ms. Warm query-embedding request: median 71 ms,
  range 66–164 ms. Median vector ranking: 0.534 ms. These exclude Apple TV input,
  production-service authorization, UI rendering and large-corpus costs.
- Three unsupported queries deliberately still returned nearest vector candidates;
  retrieval scores are not proof. The installed local `qwen3.5:9b` then passed
  three bounded evidence checks: one supported result with a literal synopsis
  quote, one wrong-series query rejected, and one invented-event query rejected.
  First verification: 7.127 s including 5.352 s model load. The two subsequent
  short rejection responses took 0.995 and 1.139 s. This does not establish the
  latency of a longer warm positive answer, or general hallucination resistance.
- Ollama reported both models resident entirely in VRAM after the checks. Driver
  backend, gaming contention, concurrent indexing/playback and idle reloads were
  not independently inspected or benchmarked.

Examples: “Haley gets in trouble with the police” → S4E7 Arrested; “Haley starts
university” → S4E2 Schooled; “Gloria keeps everyone awake by snoring” → S4E4 The
Butler's Escape. The verifier rejected “Joey breaks a chair in Friends” and
“Gloria wins a Nobel Prize” against this season's metadata; that is lack of
support in this corpus, not a claim about everything in the owner's library.

The private report, corpus, model identity, measured requests, evidence and
hash manifest are saved together in the approved folder. The result supports
independent fast matches and a separate asynchronous AI row. Before a full job,
the next useful test is a bounded mixed-series/movie corpus with ambiguous and
unsupported questions, plus representative metadata coverage and memory/latency
checks. Do not extrapolate this short season into an exact whole-library time.

## Reusable mixed-library seed and evaluation

The owner approved the subsequent 500-item mixed test and explicitly required
that testing contribute to the final database. `scripts/search_index_pilot.py`
creates an extensible item index and immutable content-addressed embedding cache,
with source/account identity, model digest, preprocessing version and text hash.
It also saves query vectors. Extending the inventory does not invalidate existing
vectors; only changed embedding text or model/preprocessing identity requires
new work. Local batch commits survive interruption. All server output remains
new immutable snapshots inside the authorized private scope.

- Actual sample: 386 episodes across 14 shows, 100 movies, 14 series records.
  Includes additional Modern Family seasons and distinct genres/media types.
- Reused all 24 original vectors, with current source-description hashes checked.
  Only 476 new document vectors were generated: 21.403 s total request time,
  including model load. Cached all 40 evaluation-query vectors as well.
- Real resume invocation found no pending documents and made zero new embedding
  requests. Integrity, item/hash/vector/FTS alignment and all 500 vectors passed.
- Current closed seed size: 4,390,912 bytes. Export verified bytes/SHA-256 hashes,
  then opened the remote snapshot read-only/immutable to check integrity/count.
  The original one-season snapshot remains intact. This is a partial real index,
  not a complete library inventory; absence cannot establish Need request.
- Queries/expected answers were selected from source descriptions before mixed
  retrieval, without looking at ranking results. This remains a curated test,
  not an independent or representative accuracy study of the full library.
- Of 34 positive questions, 33 ranked the predefined answer first and all 34
  placed it in the top three. The miss ranked an earlier Cam/school-musical
  episode ahead of the intended S4E4 music-teacher episode. The Phil/Jay fishing
  query still ranked S4E1 first without naming Modern Family.
- Four deliberately unsupported and two exploratory ambiguous queries were also
  retained. Median local text lookup 0.595 ms; warm query embedding 110.457 ms
  (maximum 117.173 ms); median NumPy vector ranking 0.116 ms. Matrix construction,
  server authorization, keyboard debounce and actual Apple TV rendering are not
  included. These measurements do not guarantee full-library/UI latency.
- Strict local-model verification passed only 10 of 13 selected checks. It
  wrongly included a college movie for Haley, accepted Lost for a plane-crash
  query explicitly naming Phil/Jay, and treated Rachel breaking Joey's chair as
  support for Joey breaking his own chair. Exact source quotes did not prevent
  these errors. Failures, original prompts/queries and evidence are preserved;
  no assertions, expected answers or ranking were changed to hide them.

The evidence supports the reusable indexing/retrieval path. A production AI
answer layer still needs character/show constraints and action/subject entailment
handling, plus honest uncertainty. A plausible scene match can help someone with
an imperfect memory, but must not be presented as proof of every detail they
typed. Do not discard or re-embed the working corpus to address this separate
answer-verification problem. No deployment or app search integration occurred.

## Automatic new-content sync and description backfill

Owner-confirmed architecture: permanent index process and local database on
Unraid; inference calls to the configured Ollama URL on the everyday PC. Fast
metadata search remains usable when inference is unavailable. Current testing
runs on the PC and exports a closed snapshot. No permanent worker, listener,
container or daily scheduler was installed by these pilots.

Required permanent flow:

1. Subscribe to the restricted user's Jellyfin `LibraryChanged` stream before
   the initial inventory. Persist/coalesce added/updated item IDs across batches.
   Re-fetch through the authorized API; source files are never edited or read
   directly. Make new metadata/text searchable as soon as the upsert commits.
2. Queue embeddings separately and persist pending work while Ollama is asleep.
   Replayed events and progress-only changes reuse matching content hashes.
   Removals become index tombstones, not deletion operations on Jellyfin/media.
3. On reconnect/restart, catch up using a saved successful-request cutoff and
   overlap through `MinDateLastSaved`; advance only after all pages commit.
   Include periodic successful full-inventory reconciliation for missed events,
   clock/paging problems, removals and permission changes. An incomplete/failed
   scan cannot justify tombstoning absent items. Folder-only events need scoped
   library reconciliation. Retain the per-account permission boundary.
4. Detect empty and recognizable placeholder overviews. Store a pending quality
   tag, retry time, attempt count and last-check time in `description_rechecks`.
   Re-fetch only flagged IDs daily. Real descriptions resolve the tag, update
   full-text immediately and enqueue only the changed document embedding.
   Titles with actual useful future-release descriptions do not need this retry
   merely because they have not aired.

Verified live in the bounded test: event connection, ForceKeepAlive/KeepAlive and
clean close with the restricted account; no actual library-change frame arrived.
The client requires its existing `ApiKey` query spelling. Two scoped API requests
on one already indexed item returned it for an old cutoff and excluded it for a
future cutoff, verifying changed-since filtering on the installed server. This
does not prove a real newly added item was processed. Local fixtures exercised
event deduplication, unchanged/changed upserts, text before embeddings and rollback.

One sampled movie had a FileFlows placeholder rather than plot text. It was
tagged and actually re-fetched once via the API; unchanged, it retains its vector
and is due for another check in 24 hours. Local fixtures verified missing/TBA
classification and resolution when useful text arrives. This is a stored queue
and bounded refetch, not an already running daily task. Opaque nonempty text can
still need quality review; recognizers are deliberately conservative.

“Instant” means promptly after Jellyfin exposes imported metadata, not at the
instant a file lands on disk. Jellyfin can delay scans and batch library-change
notifications. No setting/plugin change was made to shorten that delay. Public
API support: [changed-since requests](https://kotlin-sdk.jellyfin.org/dokka/jellyfin-model/org.jellyfin.sdk.model.api.request/-get-items-request/index.html),
[library notification/monitor delay fields](https://github.com/jellyfin/jellyfin-sdk-swift/blob/main/Sources/Entities/ServerConfiguration.swift).

## Verifier correction before the full run

The owner requested fixing the false confirmations before expanding the index.
The default `verify` entry point now invokes `independent-evidence-v5`; the old
batch checker is retained only to explain historical failures. It cannot be a
silent runtime fallback. Ordinary retrieval and the approved TV UI are unchanged.

The correction separates provenance, identity and semantic support:

- Deterministically preserve named characters and explicit show identity.
  Character aliases come from scoped Jellyfin cast roles. Shared family names
  cannot merge siblings/parents into one person. Capitalized ordinary overview
  words are not used as a lowercase-name dictionary.
- Check each candidate independently, avoiding facts leaking between titles.
  Require both the existing local generator's whole-query support vote with
  literal quotations and an independent local entailment classifier to agree.
  Neither model alone passed the role-reversal tests; their scores/votes do not
  independently prove a fact.
- Veto an active agent inferred solely from an agentless passive source clause.
  Check explicit dependent conditions separately, so agreeing on the general
  event cannot hide an unsupported deadline or extra event. These are deliberately
  conservative English safeguards, not a complete parser for all language/syntax.
- Keep disagreements, context overflow and malformed/incomplete evidence as
  possible matches; reject wrong identities. Preserve the actual episode/movie
  candidate instead of removing it just because it cannot be confirmed.
- Cache input/model-bound raw checks and reapply the current policy. Do not store
  generated assertions as library facts. Model/policy changes invalidate answer
  decisions without regenerating the unchanged document embedding index.

The independent component is the author's pinned, Apache-2.0
[DeBERTa NLI cross-encoder](https://huggingface.co/cross-encoder/nli-deberta-v3-base),
using its published CPU ONNX export. Model/tokenizer files total 253,082,944 bytes;
revision and file hashes are recorded privately and verified at load. ONNX Runtime
and tokenizers were installed in a private project environment, not the system.
Scoring is local CPU work with telemetry disabled; household text is not sent to
an external inference service. The existing local Ollama generator remains in use.
No runtime/container was installed or started on Unraid by this correction.

Final fixed-case evaluation comprises the original 13 checks, 27 additional
source-based challenges, and 16 further questions frozen before consensus testing:

- 56 evaluated cases; zero incorrect confirmations in this set.
- All 27 deliberately unsupported questions remained unconfirmed.
- All 29 legitimate target candidates retained: 23 confirmed and six possible.
  Strict fully-confirmed expectations are still 50/56, not 56/56. The six retained
  possibilities are explicitly listed in the private report; their original
  expected outcomes were not rewritten to claim more confirmations.
- 36 offline unit tests pass, covering name/show identity, ownership/actor roles,
  active/passive distinctions, additional conditions, aliases, malformed evidence,
  unavailable models and independent-check disagreement. All 56 final decisions
  replayed offline identically from saved raw checks.
- The default entry point now fails its validation gate for any false confirmation
  or dropped legitimate target. This is a validation-campaign gate, not proof of
  correctness for arbitrary new questions.
- The 500-item database's SHA-256 is unchanged. No document or query embeddings
  were generated during verifier correction. New facts are checked only for a
  query's shortlist, not by running an LLM over the full library during indexing.

The earlier single-generator, specialized-model-only and initial combined results
are preserved, including their failures. Thresholds, models, prompts and source
inputs are versioned. The final small-classifier threshold is a fixed conservative
policy, not a calibrated probability of factual correctness. These curated English
tests do not establish general accuracy, cold/warm TV latency, server CPU cost,
or actual new-content/reconnect/permission behavior of a permanent deployment.

The fix bundle is saved additively inside the approved private storage, with code,
original/final results, reusable caches, model files, requirements and hashes. The
existing database and its snapshots remain intact. Full indexing and a permanent
Unraid service/scheduler are separate next steps under the agreed deployment scope.
