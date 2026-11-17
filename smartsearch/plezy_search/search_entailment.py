"""Independent local NLI gate for search candidates; no model auto-downloads."""

import json
import math
from pathlib import Path
import re
import time

import search_evidence as evidence

VERSION = 'candidate-nli-v3'
ENTAILMENT_MIN = 0.90  # Fixed before live evaluation; not a calibrated guarantee.


def canonicalize(text, catalog, series):
    aliases = evidence.alias_roles(catalog, series)
    unique = {alias: next(iter(roles)) for alias, roles in aliases.items() if len(roles) == 1}
    if not unique:
        return text
    pattern = re.compile(r'(?<!\w)(?:'+'|'.join(re.escape(x) for x in sorted(unique,key=len,reverse=True))+r')(?!\w)',re.I)
    return pattern.sub(lambda m: unique[evidence.norm(m.group())],text)


class EntailmentModel:
    def __init__(self, provenance_path):
        import hashlib
        import onnxruntime as ort
        from tokenizers import Tokenizer
        ort.disable_telemetry_events()
        self.provenance = json.loads(Path(provenance_path).read_text())
        root = Path(self.provenance['local_directory'])
        for name in ('config.json','tokenizer.json','onnx/model_quint8_avx2.onnx'):
            p = root/name
            expected = self.provenance['files'][name]
            if p.stat().st_size != expected['bytes'] or hashlib.sha256(p.read_bytes()).hexdigest() != expected['sha256']:
                raise ValueError('Local entailment model integrity mismatch')
        config = json.loads((root/'config.json').read_text())
        self.labels = {int(k):v for k,v in config['id2label'].items()}
        if set(self.labels.values()) != {'contradiction','entailment','neutral'}:
            raise ValueError('Unexpected model label mapping')
        self.tokenizer = Tokenizer.from_file(str(root/'tokenizer.json'))
        self.tokenizer.no_truncation()
        self.tokenizer.no_padding()
        options = ort.SessionOptions()
        options.intra_op_num_threads = 4
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        self.session = ort.InferenceSession(str(root/'onnx/model_quint8_avx2.onnx'),
                                          sess_options=options,providers=['CPUExecutionProvider'])
        self.input_names = {x.name for x in self.session.get_inputs()}
        self.max_tokens = config['max_position_embeddings']

    def score(self, premise, hypothesis):
        import numpy as np
        start = time.perf_counter()
        encoded = self.tokenizer.encode(premise,hypothesis)
        if len(encoded.ids) > self.max_tokens:
            return {'available':False,'reason':'context_limit','tokens':len(encoded.ids)}
        values = {'input_ids':encoded.ids,'attention_mask':encoded.attention_mask,
                  'token_type_ids':encoded.type_ids}
        if not self.input_names <= values.keys():
            raise ValueError('Unexpected ONNX model inputs')
        inputs = {name:np.array([values[name]],dtype=np.int64) for name in self.input_names}
        logits = np.asarray(self.session.run(None,inputs)[0][0],dtype=np.float64)
        if logits.shape != (3,) or not np.isfinite(logits).all():
            raise ValueError('Invalid entailment model logits')
        p = np.exp(logits-logits.max());p/=p.sum()
        scores = {self.labels[i]:float(v) for i,v in enumerate(p)}
        return {'available':True,'scores':scores,'tokens':len(encoded.ids),
                'wall_ms':round((time.perf_counter()-start)*1000,3)}


def decide(query, candidate, catalog, required, result):
    gate = evidence.precheck(query,candidate,catalog,required)
    if not gate['eligible']:
        return {'confirmed':False,'reason':'identity_constraint',**gate}
    scores = result.get('scores',{})
    if not result.get('available') or set(scores) != {'entailment','contradiction','neutral'}:
        return {'confirmed':False,'reason':'unavailable_evidence'}
    if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) or not 0<=v<=1 for v in scores.values()) or abs(sum(scores.values())-1)>0.00001:
        return {'confirmed':False,'reason':'invalid_scores'}
    if scores['entailment'] < ENTAILMENT_MIN or scores['entailment'] <= max(scores['contradiction'],scores['neutral']):
        return {'confirmed':False,'reason':'not_entailed'}
    return {'confirmed':True,'reason':'supported_by_synopsis',
            'evidence':[candidate['overview']]}
