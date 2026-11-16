#!/usr/bin/env python3
"""Repair/evaluate evidence verification without re-embedding the library."""

import argparse
import hashlib
import json
from pathlib import Path
import statistics

import search_evidence as evidence
import search_index_pilot as pilot

PLAN = pilot.ROOT / '.env.plezy-search-verifier-cases.json'
CATALOG = pilot.ROOT / '.env.plezy-search-verifier-catalog.json'
CACHE = pilot.ROOT / '.env.plezy-search-verifier-cache'


def catalog():
    state = pilot.get_state()
    if CATALOG.exists():
        result = json.loads(CATALOG.read_text())
        if result['source_key'] != state['source']['key']:
            raise pilot.PilotError('Verifier catalog account/source differs')
        return result
    corpus = json.loads((pilot.work(state)/'corpus.json').read_text())
    jf, headers, source = pilot.login()
    if source['key'] != state['source']['key']:
        raise pilot.PilotError('Verifier source/account differs')
    shows = corpus['series']
    data, ms = pilot.items(jf, headers, source['user_id'], Ids=','.join(s['Id'] for s in shows),
                           Fields='People', Limit=len(shows), IncludeItemTypes='Series')
    wanted = {s['Id'] for s in shows}
    roles = {}
    for show in data.get('Items', []):
        if show['Id'] not in wanted:
            raise pilot.PilotError('Unexpected character-catalog response')
        roles[show['Name']] = sorted({pilot.plain(p.get('Role')) for p in show.get('People', [])
                                     if p.get('Type') == 'Actor' and p.get('Role')})
    result = {'source_key': source['key'], 'created_utc': pilot.utc(),
              'titles': sorted({s['Name'] for s in shows}), 'roles': roles,
              'role_source': 'Jellyfin cast Role metadata, not model-generated aliases', 'request_ms': ms}
    pilot.save(CATALOG, result, True)
    print(pilot.packed({'phase':'character_catalog','shows':len(roles),
                        'roles':sum(len(v) for v in roles.values())}),flush=True)
    return result


def run():
    state = pilot.get_state()
    db_path = pilot.work(state)/'index.sqlite'
    db_hash = hashlib.sha256(db_path.read_bytes()).hexdigest()
    cat = catalog()
    plan = json.loads(PLAN.read_text())
    original = json.loads((pilot.work(state)/'retrieval-results.json').read_text())
    all_candidates = [c for r in original for c in r['semantic_top8']]
    cases = []
    for r in original:
        if r.get('verify'):
            cases.append({'id':r['id'],'query':r['query'],'expected_keys':r.get('expected_keys',[]),
                          'expect_abstain':r.get('expect_abstain',False),'group':'original_regression',
                          'candidates':r['semantic_top8']})
    cases.extend(plan['cases'])
    _,_,ol,headers = pilot.config()
    tags,_ = pilot.api(ol,'/api/tags',headers)
    model = next((m for m in tags.get('models',[]) if m['name']=='qwen3.5:9b' and not m.get('remote_host') and not m.get('remote_model')),None)
    if not model:
        raise pilot.PilotError('Existing local verification model not available')
    policy_hash = pilot.sha(Path(evidence.__file__).read_bytes())
    run_key = pilot.sha(pilot.packed({'policy':policy_hash,'plan':plan,'original':original,'model':model['digest'],'catalog':cat}))[:16]
    run_dir = pilot.work(state)/('verification-fix-'+run_key)
    run_dir.mkdir(mode=0o700,exist_ok=True)
    frozen = run_dir/'frozen-cases.json'
    if not frozen.exists():
        pilot.save(frozen,{'version':evidence.VERSION,'guard_sha256':policy_hash,'model':{'name':model['name'],'digest':model['digest']},'cases':cases},True)
    CACHE.mkdir(mode=0o700,exist_ok=True)
    path = run_dir/'results.json'
    results = json.loads(path.read_text()) if path.exists() else []
    complete = {r['id'] for r in results}
    for case in cases:
        if case['id'] in complete:
            continue
        required = evidence.constraints(case['query'],cat,all_candidates)
        inspected = []
        confirmed = []
        for candidate in case['candidates']:
            gate = evidence.precheck(case['query'],candidate,cat,required)
            if not gate['eligible']:
                inspected.append({'key':candidate['key'],'label':candidate['label'],
                                  'guard':{'confirmed':False,'reason':'identity_constraint',**gate},
                                  'model_called':False})
                continue
            payload = {'model':model['name'],'prompt':evidence.prompt(case['query'],candidate),
                       'stream':False,'think':False,'format':evidence.SCHEMA,'keep_alive':'5m',
                       'options':{'temperature':0,'num_ctx':4096,'num_predict':384}}
            proof_key = pilot.sha(pilot.packed({'payload':payload,'model_digest':model['digest'],
                                              'source_key':state['source']['key'],'item_key':candidate['key']}))
            cache_path = CACHE/(proof_key+'.json')
            hit = cache_path.exists()
            if hit:
                raw = json.loads(cache_path.read_text())
            else:
                data, ms = pilot.api(ol,'/api/generate',headers,payload,timeout=60)
                try:
                    proof = json.loads(data.get('response',''))
                except (TypeError,ValueError):
                    proof = None
                raw = {'proof':proof,'raw_response':data.get('response',''),
                       'wall_ms':ms,'load_ms':round(data.get('load_duration',0)/1e6,3),
                       'output_tokens':data.get('eval_count'),'model_digest':model['digest'],
                       'created_utc':pilot.utc(),'cache_key':proof_key}
                pilot.save(cache_path,raw,True)
            guard = evidence.validate(case['query'],candidate,cat,required,raw['proof'])
            record = {'key':candidate['key'],'label':candidate['label'],'guard':guard,
                      'model_called':not hit,'proof_cache_hit':hit,'cache_key':proof_key,
                      'proof':raw['proof'],'wall_ms':raw['wall_ms']}
            inspected.append(record)
            if guard['confirmed']:
                confirmed.append({'key':candidate['key'],'label':candidate['label'],
                                  'evidence':guard['evidence']})
        expected = set(case.get('expected_keys',[]))
        passed = not confirmed if case['expect_abstain'] else bool(confirmed) and all(c['key'] in expected for c in confirmed)
        result = {'id':case['id'],'query':case['query'],'group':case['group'],
                  'required':required,'passed':passed,'confirmed':confirmed,'inspected':inspected,
                  'expected_keys':case.get('expected_keys',[]),'expect_abstain':case['expect_abstain']}
        results.append(result)
        pilot.save(path,results)
        print(pilot.packed({'phase':'candidate_verification','id':case['id'],'query':case['query'],
                            'passed':passed,'confirmed':[c['label'] for c in confirmed],
                            'identity_rejections':sum(i['guard']['reason']=='identity_constraint' for i in inspected)}),flush=True)
    current,_ = pilot.api(ol,'/api/tags',headers)
    if not any(m['name']==model['name'] and m['digest']==model['digest'] for m in current.get('models',[])):
        raise pilot.PilotError('Verification model changed during validation')
    after = hashlib.sha256(db_path.read_bytes()).hexdigest()
    if after != db_hash:
        raise pilot.PilotError('Index changed during verifier-only validation')
    summary = {'checks':len(results),'passed':sum(r['passed'] for r in results),
               'groups':{group:{'checks':sum(r['group']==group for r in results),
                                'passed':sum(r['group']==group and r['passed'] for r in results)}
                         for group in sorted({r['group'] for r in results})},
               'false_confirmations':sum(any(c['key'] not in r['expected_keys'] for c in r['confirmed']) for r in results),
               'positive_queries_without_confirmation':sum(not r['expect_abstain'] and not r['confirmed'] for r in results),
               'database_sha256_unchanged':after,'document_embedding_requests':0,'query_embedding_requests':0,
               'guard_sha256':policy_hash,'verifier_version':evidence.VERSION,'model_digest':model['digest']}
    pilot.save(run_dir/'summary.json',summary)
    state['verifier_fix']={'directory':str(run_dir),'summary':summary}
    pilot.save(pilot.STATE,state)
    print(pilot.packed({'phase':'verifier_fix_summary',**summary}),flush=True)


def nli():
    import search_entailment as entailment
    state=pilot.get_state()
    db_path=pilot.work(state)/'index.sqlite'
    before=pilot.sha(db_path.read_bytes())
    cat=json.loads(CATALOG.read_text())
    if cat['source_key']!=state['source']['key']:
        raise pilot.PilotError('NLI catalog account/source differs')
    original=json.loads((pilot.work(state)/'retrieval-results.json').read_text())
    plan=json.loads(PLAN.read_text())
    cases=[{'id':r['id'],'query':r['query'],'expected_keys':r.get('expected_keys',[]),
            'expect_abstain':r.get('expect_abstain',False),'group':'original_regression',
            'candidates':r['semantic_top8']} for r in original if r.get('verify')]
    cases.extend(plan['cases'])
    population=[c for r in original for c in r['semantic_top8']]
    provenance=pilot.ROOT/'.env.plezy-search-nli-provenance.json'
    model=entailment.EntailmentModel(provenance)
    policy=pilot.sha(Path(evidence.__file__).read_bytes()+Path(entailment.__file__).read_bytes())
    run_key=pilot.sha(pilot.packed({'policy':policy,'cases':cases,'catalog':cat,
                                   'model':model.provenance['files']}))[:16]
    directory=pilot.work(state)/('verification-nli-'+run_key)
    directory.mkdir(mode=0o700,exist_ok=True)
    frozen=directory/'frozen-cases.json'
    if not frozen.exists():
        pilot.save(frozen,{'version':entailment.VERSION,'threshold':entailment.ENTAILMENT_MIN,
                          'policy_sha256':policy,'cases':cases},True)
    cache=pilot.ROOT/'.env.plezy-search-nli-cache'
    cache.mkdir(mode=0o700,exist_ok=True)
    path=directory/'results.json'
    results=json.loads(path.read_text()) if path.exists() else []
    complete={r['id'] for r in results}
    for case in cases:
        if case['id'] in complete:
            continue
        required=evidence.constraints(case['query'],cat,population)
        inspected=[];confirmed=[]
        for candidate in case['candidates']:
            gate=evidence.precheck(case['query'],candidate,cat,required)
            if not gate['eligible']:
                inspected.append({'key':candidate['key'],'label':candidate['label'],
                                  'guard':{'confirmed':False,'reason':'identity_constraint',**gate}})
                continue
            identity=candidate['series'] if candidate['kind']=='Episode' else candidate['title']
            premise='Title: '+identity+'. '+candidate['overview']
            premise=entailment.canonicalize(premise,cat,candidate.get('series',''))
            hypothesis=entailment.canonicalize(case['query'],cat,candidate.get('series',''))
            key=pilot.sha(pilot.packed({'model':model.provenance['files'],'premise':premise,
                                       'hypothesis':hypothesis,'source':state['source']['key']}))
            p=cache/(key+'.json')
            hit=p.exists()
            if hit:
                scored=json.loads(p.read_text())
            else:
                scored=model.score(premise,hypothesis)
                pilot.save(p,scored,True)
            decision=entailment.decide(case['query'],candidate,cat,required,scored)
            inspected.append({'key':candidate['key'],'label':candidate['label'],'guard':decision,
                              'score':scored,'cache_key':key,'cache_hit':hit})
            if decision['confirmed']:
                confirmed.append({'key':candidate['key'],'label':candidate['label'],
                                  'evidence':decision['evidence']})
        expected=set(case['expected_keys'])
        passed=not confirmed if case['expect_abstain'] else bool(confirmed) and all(c['key'] in expected for c in confirmed)
        result={'id':case['id'],'query':case['query'],'group':case['group'],'required':required,
                'passed':passed,'confirmed':confirmed,'expected_keys':case['expected_keys'],
                'expect_abstain':case['expect_abstain'],'inspected':inspected}
        results.append(result);pilot.save(path,results)
        print(pilot.packed({'phase':'nli_verification','id':case['id'],'query':case['query'],
                            'passed':passed,'confirmed':[r['label'] for r in confirmed]}),flush=True)
    after=pilot.sha(db_path.read_bytes())
    if before!=after:
        raise pilot.PilotError('Index changed during NLI-only validation')
    scores=[i['score'] for r in results for i in r['inspected'] if 'score' in i]
    summary={'checks':len(results),'passed':sum(r['passed'] for r in results),
             'groups':{g:{'checks':sum(r['group']==g for r in results),'passed':sum(r['group']==g and r['passed'] for r in results)} for g in sorted({r['group'] for r in results})},
             'false_confirmations':sum(any(c['key'] not in r['expected_keys'] for c in r['confirmed']) for r in results),
             'positive_queries_without_confirmation':sum(not r['expect_abstain'] and not r['confirmed'] for r in results),
             'negative_queries':sum(r['expect_abstain'] for r in results),
             'negative_queries_rejected':sum(r['expect_abstain'] and not r['confirmed'] for r in results),
             'median_candidate_cpu_ms':round(statistics.median(x['wall_ms'] for x in scores if x.get('available')),3),
             'database_sha256_unchanged':after,'document_embedding_requests':0,'query_embedding_requests':0,
             'threshold':entailment.ENTAILMENT_MIN,'policy_sha256':policy,'verifier_version':entailment.VERSION,
             'model_repo':model.provenance['model_repo'],'model_revision':model.provenance['revision']}
    pilot.save(directory/'summary.json',summary)
    state['verifier_nli_fix']={'directory':str(directory),'summary':summary}
    pilot.save(pilot.STATE,state)
    print(pilot.packed({'phase':'nli_summary',**summary}),flush=True)


def consensus_run():
    import search_entailment as entailment
    state=pilot.get_state()
    db_path=pilot.work(state)/'index.sqlite'
    original_hash=pilot.sha(db_path.read_bytes())
    cat=json.loads(CATALOG.read_text())
    if cat['source_key']!=state['source']['key']:
        raise pilot.PilotError('Verifier catalog account/source differs')
    original=json.loads((pilot.work(state)/'retrieval-results.json').read_text())
    cases=[{'id':r['id'],'query':r['query'],'expected_keys':r.get('expected_keys',[]),
            'expect_abstain':r.get('expect_abstain',False),'group':'original_regression',
            'candidates':r['semantic_top8']} for r in original if r.get('verify')]
    cases.extend(json.loads(PLAN.read_text())['cases'])
    cases.extend(json.loads((pilot.ROOT/'.env.plezy-search-verifier-fresh-cases.json').read_text())['cases'])
    population=[c for r in original for c in r['semantic_top8']]
    model=entailment.EntailmentModel(pilot.ROOT/'.env.plezy-search-nli-provenance.json')
    _,_,ol,headers=pilot.config()
    tags,_=pilot.api(ol,'/api/tags',headers)
    generator=next((m for m in tags.get('models',[]) if m['name']=='qwen3.5:9b' and not m.get('remote_host') and not m.get('remote_model')),None)
    if not generator:
        raise pilot.PilotError('Existing local generator unavailable')
    policy=pilot.sha(Path(evidence.__file__).read_bytes()+Path(entailment.__file__).read_bytes())
    version=evidence.VERSION
    run_key=pilot.sha(pilot.packed({'version':version,'policy':policy,'cases':cases,'catalog':cat,
                                   'nli':model.provenance['files'],'generator':generator['digest']}))[:16]
    directory=pilot.work(state)/('verification-consensus-'+run_key)
    directory.mkdir(mode=0o700,exist_ok=True)
    if not (directory/'frozen-cases.json').exists():
        pilot.save(directory/'frozen-cases.json',{'version':version,'threshold':entailment.ENTAILMENT_MIN,
                   'policy_sha256':policy,'cases':cases},True)
    nli_cache=pilot.ROOT/'.env.plezy-search-nli-cache'
    nli_cache.mkdir(mode=0o700,exist_ok=True);CACHE.mkdir(mode=0o700,exist_ok=True)
    path=directory/'results.json'
    results=json.loads(path.read_text()) if path.exists() else []
    completed={r['id'] for r in results}
    for case in cases:
        if case['id'] in completed:
            continue
        required=evidence.constraints(case['query'],cat,population)
        inspected=[];confirmed=[]
        for candidate in case['candidates']:
            identity_gate=evidence.precheck(case['query'],candidate,cat,required)
            if not identity_gate['eligible']:
                inspected.append({'key':candidate['key'],'label':candidate['label'],
                    'guard':{'confirmed':False,'status':'rejected','reason':'identity_constraint',**identity_gate}})
                continue
            identity=candidate['series'] if candidate['kind']=='Episode' else candidate['title']
            premise=entailment.canonicalize('Title: '+identity+'. '+candidate['overview'],cat,candidate.get('series',''))
            hypothesis=entailment.canonicalize(case['query'],cat,candidate.get('series',''))
            score_key=pilot.sha(pilot.packed({'model':model.provenance['files'],'premise':premise,
                                            'hypothesis':hypothesis,'source':state['source']['key']}))
            score_path=nli_cache/(score_key+'.json')
            if score_path.exists():
                scored=json.loads(score_path.read_text())
            else:
                scored=model.score(premise,hypothesis);pilot.save(score_path,scored,True)
            scored=dict(scored)
            scored['dependent_claims']=[]
            for claim in evidence.dependent_claims(case['query']):
                claim_hypothesis=entailment.canonicalize(claim,cat,candidate.get('series',''))
                claim_key=pilot.sha(pilot.packed({'model':model.provenance['files'],'premise':premise,
                                                'hypothesis':claim_hypothesis,'source':state['source']['key']}))
                claim_path=nli_cache/(claim_key+'.json')
                if claim_path.exists():
                    checked=json.loads(claim_path.read_text())
                else:
                    checked=model.score(premise,claim_hypothesis);pilot.save(claim_path,checked,True)
                scored['dependent_claims'].append({'claim':claim,'result':checked})
            nli_vote=entailment.decide(case['query'],candidate,cat,required,scored)
            raw=None;proof_key=None;proof_hit=None
            if nli_vote['confirmed']:
                payload={'model':generator['name'],'prompt':evidence.prompt(case['query'],candidate),
                         'stream':False,'think':False,'format':evidence.SCHEMA,'keep_alive':'5m',
                         'options':{'temperature':0,'num_ctx':4096,'num_predict':384}}
                proof_key=pilot.sha(pilot.packed({'payload':payload,'model_digest':generator['digest'],
                                                'source_key':state['source']['key'],'item_key':candidate['key']}))
                proof_path=CACHE/(proof_key+'.json');proof_hit=proof_path.exists()
                if proof_hit:
                    raw=json.loads(proof_path.read_text())
                else:
                    data,ms=pilot.api(ol,'/api/generate',headers,payload,timeout=60)
                    try:proof=json.loads(data.get('response',''))
                    except (TypeError,ValueError):proof=None
                    raw={'proof':proof,'raw_response':data.get('response',''),'wall_ms':ms,
                         'load_ms':round(data.get('load_duration',0)/1e6,3),'output_tokens':data.get('eval_count'),
                         'model_digest':generator['digest'],'created_utc':pilot.utc(),'cache_key':proof_key}
                    pilot.save(proof_path,raw,True)
            guard=evidence.consensus(case['query'],candidate,cat,required,
                                     raw['proof'] if raw else None,scored)
            inspected.append({'key':candidate['key'],'label':candidate['label'],'guard':guard,
                              'nli':scored,'nli_cache_key':score_key,'proof':raw['proof'] if raw else None,
                              'proof_cache_key':proof_key,'proof_cache_hit':proof_hit,
                              'generator_wall_ms':raw['wall_ms'] if raw else None})
            if guard['confirmed']:
                confirmed.append({'key':candidate['key'],'label':candidate['label'],'evidence':guard['evidence']})
        expected=set(case['expected_keys'])
        passed=not confirmed if case['expect_abstain'] else bool(confirmed) and all(c['key'] in expected for c in confirmed)
        possible=[{'key':i['key'],'label':i['label'],'reason':i['guard']['reason']}
                  for i in inspected if i['guard'].get('status')=='possible']
        retained=any(c['key'] in expected for c in confirmed+possible)
        result={'id':case['id'],'query':case['query'],'group':case['group'],'required':required,
                'passed':passed,'confirmed':confirmed,'expected_keys':case['expected_keys'],
                'possible':possible,'retained_expected_match':retained,
                'expect_abstain':case['expect_abstain'],'inspected':inspected}
        results.append(result);pilot.save(path,results)
        print(pilot.packed({'phase':'consensus_verification','id':case['id'],'passed':passed,
                            'query':case['query'],'confirmed':[r['label'] for r in confirmed]}),flush=True)
    current,_=pilot.api(ol,'/api/tags',headers)
    if not any(m['name']==generator['name'] and m['digest']==generator['digest'] for m in current.get('models',[])):
        raise pilot.PilotError('Generator model changed during validation')
    after=pilot.sha(db_path.read_bytes())
    if after!=original_hash:
        raise pilot.PilotError('Index changed during verifier-only work')
    summary={'version':version,'checks':len(results),'passed':sum(r['passed'] for r in results),
             'groups':{g:{'checks':sum(r['group']==g for r in results),'passed':sum(r['group']==g and r['passed'] for r in results)} for g in sorted({r['group'] for r in results})},
             'false_confirmations':sum(any(c['key'] not in r['expected_keys'] for c in r['confirmed']) for r in results),
             'positive_queries':sum(not r['expect_abstain'] for r in results),
             'positive_queries_without_confirmation':sum(not r['expect_abstain'] and not r['confirmed'] for r in results),
             'positive_queries_retaining_expected_candidate':sum(not r['expect_abstain'] and r['retained_expected_match'] for r in results),
             'negative_queries':sum(r['expect_abstain'] for r in results),
             'negative_queries_rejected':sum(r['expect_abstain'] and not r['confirmed'] for r in results),
             'database_sha256_unchanged':after,'document_embedding_requests':0,'query_embedding_requests':0,
             'threshold':entailment.ENTAILMENT_MIN,'policy_sha256':policy,
             'nli_model_repo':model.provenance['model_repo'],'nli_revision':model.provenance['revision'],
             'generator_digest':generator['digest']}
    summary['quality_gate_passed']=(summary['false_confirmations']==0
        and summary['negative_queries']>=27
        and summary['negative_queries_rejected']==summary['negative_queries']
        and summary['positive_queries']>=29
        and summary['positive_queries_retaining_expected_candidate']==summary['positive_queries'])
    pilot.save(directory/'summary.json',summary)
    state['verifier_consensus_fix']={'directory':str(directory),'summary':summary}
    pilot.save(pilot.STATE,state)
    print(pilot.packed({'phase':'consensus_summary',**summary}),flush=True)
    if not summary['quality_gate_passed']:
        raise pilot.PilotError('Verifier quality gate failed; raw results preserved, do not promote')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase',choices=['catalog','run','nli','consensus_run'])
    args=parser.parse_args()
    try:
        globals()[args.phase]()
    except Exception as error:
        print(pilot.packed({'ok':False,'error':str(error) if isinstance(error,pilot.PilotError) else type(error).__name__}),flush=True)
        raise SystemExit(1)
