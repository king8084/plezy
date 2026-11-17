"""Search quality + speed benchmark against a real index (read-only).

Usage: python3 smartsearch/tests/benchmark.py INDEX.sqlite CASES.json [CASES.json ...] --out RESULTS.json
       [--access ACCESS.json --model-digest D] [--verify-provenance NLI.json --verify-cache CACHE.sqlite]

Case formats (private files; they describe the owner's library):
  pilot:  {"id","query","expected_keys":["<source>:<item_id>"],"expect_abstain"}
  new:    {"id","query","mode":"instant|smart","expect":{
              "title": "Breaking Bad" | "episode": {"series","season","episode"} | "item_ids": [...]},
           "all": {"kind": "Series", "rating_gt": 8, "genre_any": [...], "year_min", "year_max",
                   "person": "...", "studio_any": [...], "runtime_max": 90, "language": "ko"},
           "top": 10}
Results are written to --out; nothing in the index is modified.
"""

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from plezy_search.common import norm  # noqa: E402
from plezy_search.search import Engine  # noqa: E402


def expected_ids(engine, case):
    if case.get('expected_keys'):
        return {k.split(':', 1)[1] for k in case['expected_keys']}
    exp = case.get('expect') or {}
    if 'item_ids' in exp:
        return set(exp['item_ids'])
    if 'title' in exp:
        rows = engine.db.execute("SELECT item_id, title FROM items WHERE active=1 AND kind!='Episode'").fetchall()
        return {r[0] for r in rows if norm(r[1]) == norm(exp['title'])}
    if 'episode' in exp:
        e = exp['episode']
        return {r[0] for r in engine.db.execute(
            'SELECT item_id FROM items WHERE active=1 AND series=? AND season=? AND episode=?',
            (e['series'], e['season'], e['episode']))}
    return set()


def violations(engine, results, rules, top):
    bad = []
    for r in results[:top]:
        row = engine.db.execute('SELECT kind, rating, year, runtime_min, language, series_id FROM items WHERE item_id=?',
                                (r['id'],)).fetchone()
        kind, rating, year, runtime, language, series_id = row
        owner = series_id if kind == 'Episode' else r['id']
        terms = engine.db.execute('SELECT field, norm FROM item_terms WHERE item_id=?', (owner,)).fetchall()
        genres = {n for f, n in terms if f == 'genre'}
        reasons = []
        if 'kind' in rules and kind != rules['kind']:
            reasons.append('kind')
        if 'rating_gt' in rules and not (rating is not None and rating > rules['rating_gt']):
            reasons.append('rating')
        if 'genre_any' in rules and not genres & {norm(g) for g in rules['genre_any']}:
            reasons.append('genre')
        if 'year_min' in rules and not (year and year >= rules['year_min']):
            reasons.append('year')
        if 'year_max' in rules and not (year and year <= rules['year_max']):
            reasons.append('year')
        if 'runtime_max' in rules and not (runtime and runtime <= rules['runtime_max']):
            reasons.append('runtime')
        if 'person' in rules and (('person', norm(rules['person'])) not in set(terms)):
            reasons.append('person')
        if 'studio_any' in rules and not {n for f, n in terms if f == 'studio'} & {norm(s) for s in rules['studio_any']}:
            reasons.append('studio')
        if 'language' in rules and language != rules['language']:
            reasons.append('language')
        if reasons:
            bad.append({'title': r['title'], 'failed': reasons})
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('index')
    ap.add_argument('cases', nargs='+')
    ap.add_argument('--out', required=True)
    ap.add_argument('--access')
    ap.add_argument('--model-digest')
    ap.add_argument('--verify-provenance')
    ap.add_argument('--verify-cache')
    args = ap.parse_args()
    ollama = model = None
    if args.access:
        from plezy_search.clients import Ollama
        model = {'name': 'embeddinggemma:300m', 'digest': args.model_digest}
        ollama = Ollama(json.loads(Path(args.access).read_text()), model)
    engine = Engine(args.index, ollama, model)
    if args.verify_provenance:
        from plezy_search.verify import Verifier
        engine.verifier = Verifier(engine, json.loads(Path(args.access).read_text()), args.verify_provenance,
                                   args.verify_cache)
    cases = []
    for path in args.cases:
        data = json.loads(Path(path).read_text())
        cases += data['cases'] if isinstance(data, dict) else data
    out, timings = [], {'instant': [], 'smart': [], 'embed': [], 'rerank': []}
    for case in cases:
        if case.get('expect_abstain') or (not case.get('expected_keys') and not case.get('expect') and not case.get('all')):
            continue
        mode = case.get('mode', 'smart')
        want = expected_ids(engine, case)
        res = {'id': case['id'], 'query': case['query'], 'mode': mode}
        inst = engine.instant(case['query'], 40)
        timings['instant'].append(inst['took_ms'])
        res['instant_rank'] = next((n + 1 for n, r in enumerate(inst['results'])
                                    if r['id'] in want or set(r.get('other_ids', [])) & want), None)
        if mode == 'smart' and ollama:
            sm = engine.smart(case['query'], 20, verify=bool(engine.verifier), confirm=False)
            timings['smart'].append(sm['took_ms'])
            if not sm['query_vector_cached']:
                timings['embed'].append(sm['embed_ms'])
            if sm.get('verify_ms') is not None:
                timings['rerank'].append(sm['verify_ms'])
            res['smart_rank'] = next((n + 1 for n, r in enumerate(sm['results']) if r['id'] in want), None)
            res['smart_top3'] = [(r['title'], r.get('series'), r.get('season'), r.get('episode'), r.get('match'))
                                 for r in sm['results'][:3]]
        if case.get('all'):
            res['rule_violations'] = violations(engine, inst['results'], case['all'], case.get('top', 10))
            res['result_count'] = len(inst['results'])
            res['understood'] = inst['understood']
        res['expected_found'] = bool(want)
        out.append(res)

    def rate(key, n):
        rows = [r for r in out if r.get('expected_found') and key in r]
        return f"{sum(1 for r in rows if r[key] and r[key] <= n)}/{len(rows)}"

    def pct(values, p):
        return round(sorted(values)[min(len(values) - 1, int(len(values) * p))], 1) if values else None

    summary = {
        'cases': len(out),
        'instant_top1': rate('instant_rank', 1), 'instant_top3': rate('instant_rank', 3),
        'smart_top1': rate('smart_rank', 1), 'smart_top3': rate('smart_rank', 3), 'smart_top10': rate('smart_rank', 10),
        'filter_cases_clean': f"{sum(1 for r in out if 'rule_violations' in r and not r['rule_violations'] and r['result_count'])}/"
                              f"{sum(1 for r in out if 'rule_violations' in r)}",
        'instant_ms_p50': pct(timings['instant'], .5), 'instant_ms_p95': pct(timings['instant'], .95),
        'smart_ms_p50': pct(timings['smart'], .5), 'smart_ms_p95': pct(timings['smart'], .95),
        'query_embed_ms_p50': pct(timings['embed'], .5), 'rerank_ms_p50': pct(timings['rerank'], .5),
    }
    Path(args.out).write_text(json.dumps({'summary': summary, 'results': out}, ensure_ascii=False, indent=1))
    print(json.dumps(summary, indent=1))


if __name__ == '__main__':
    main()
