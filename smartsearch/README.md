# Plezy smart search

An always-on search service for the owner's Jellyfin library. It runs in one
dedicated container on the server, and the Plezy app queries it over the LAN.

## What it does

| Path | Speed | Needs Ollama? | Example |
|---|---|---|---|
| Instant (`/v1/search`) | ~5–60 ms on the server | No | `sci fi shows over 8`, `brekaing bad`, `tom hanks movies` |
| Smart (`/v1/smart`) | embedding + rank, sub-second when warm | For new queries | `the friends episode where joey breaks the chair` |
| Confirm (`/v1/verify`) | seconds (second model vote) | Yes | labels results *confirmed* or *possible* |

- **Query understanding without AI**: kind (shows/movies/episodes), genre (TV and
  movie vocabularies differ: "Sci-Fi & Fantasy" vs "Science Fiction"), IMDb
  rating (Jellyfin `CommunityRating` on this server), years and decades,
  runtime, language, network/studio, ended/running, cast. Genre and language
  words inside a plot description are ranking hints, not filters.
- **Titles first**: an exact title beats any filter reading ("modern family").
  Typos fall back to trigram plus edit similarity.
- **Show-scoped episodes**: "<show> episode where …" searches that show's episodes.
- **Smart**: query embedding fused with full text by rank, filtered by the same
  parser, then re-ranked by the local evidence checker (`verify.py`, wrapping the
  unchanged `search_evidence` / `search_entailment` policy, independent-evidence-v5).
  Only agreement between the local NLI model and the generator vote is
  "confirmed"; everything else stays "possible". Results are never dropped
  because they can't be confirmed.

## Indexer (`indexer.py`)

- Reads Jellyfin through its API with a restricted account (non-admin, deletion
  disabled); login refuses anything else. It never touches media or Jellyfin files.
- Initial import, checkpointed per page, then embeddings in batches. Vectors are
  content-addressed (`model digest + format + sha(document)`), so unchanged items,
  replayed events and rating/progress-only changes never trigger new embeddings.
  The pilot's 500 vectors carried over this way.
- New content: live `LibraryChanged` events, plus a catch-up every minute
  (`MinDateLastSaved`) and after every reconnect.
- Incomplete metadata (missing or placeholder description, upcoming release, no
  rating or genres) is tagged and re-read daily; after 30 attempts, weekly. Tags
  clear themselves when real data arrives. Jellyfin has to refresh the metadata
  itself; this service never triggers refreshes.
- Daily reconciliation hides items Jellyfin no longer returns, and only after a
  complete pass. Hiding is a flag; nothing is deleted.

## Safety rules (owner)

- **Nothing on the server is ever deleted**: SQLite uses `journal_mode=PERSIST`
  (WAL would delete its side file), status files are rewritten in place, and code
  updates reload from the mounted folder instead of replacing the container.
- The container writes only to `smartsearch/live`; `code`, `config` and `models`
  are mounted read-only. It runs as 99:100 with all capabilities dropped and a
  read-only root filesystem.
- Credentials, addresses and the API key live only in the private config
  folder, never in this repository.

## Layout on the server (`smartsearch/`)

```
code/      plezy_search/ + docker/ (Dockerfile, hash-pinned requirements)   -> /code   (ro)
config/    access.json, settings.json, service.json, nli-provenance.json    -> /config (ro)
models/    NLI model files (hash-verified at load)                          -> /models (ro)
live/      index.sqlite, status.json, logs, snapshots, verify-cache         -> /data   (rw)
```

## Development

```
python3 -m unittest discover -s smartsearch/tests -p 'test_*.py'
python3 smartsearch/tests/benchmark.py INDEX.sqlite CASES.json --out RESULTS.json [--access ... --model-digest ...]
```
Benchmark cases describe the owner's library and are kept in private files.
