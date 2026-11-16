import copy
import unittest

import search_evidence as evidence
import search_entailment as entailment


class EvidenceValidationTest(unittest.TestCase):
    def setUp(self):
        self.catalog = {'titles': ['Garden Stories', 'Friends', 'Lost'],
                        'roles': {'Garden Stories': ['Mira Vale', 'Oren Vale', 'Ada Quinn']}}
        self.candidate = {'kind': 'Episode', 'series': 'Garden Stories', 'title': 'The Chair',
                          'overview': "Mira accidentally breaks Oren's armchair while Ada watches."}
        self.query = "Mira breaks Oren's armchair"
        self.proof = {'decision': 'entailed', 'evidence': [self.candidate['overview']],
                      'unsupported_details': [], 'actor_relation': 'aligned',
                      'query_actor': 'Mira', 'source_actors': ['Mira'],
                      'source_action': 'breaks', 'source_voice': 'active'}

    def check(self, query=None, candidate=None, proof=None):
        query = self.query if query is None else query
        candidate = self.candidate if candidate is None else candidate
        proof = self.proof if proof is None else proof
        required = evidence.constraints(query, self.catalog, [candidate])
        return evidence.validate(query, candidate, self.catalog, required, proof)

    def test_supported_actor_and_object_pass(self):
        self.assertTrue(self.check()['confirmed'])

    def test_changed_name_is_rejected_even_with_valid_quote(self):
        self.assertEqual(self.check(query="Inez breaks Oren's armchair")['reason'], 'identity_constraint')

    def test_lowercase_character_constraints_are_preserved(self):
        self.assertFalse(self.check(query='oren starts university')['confirmed'])

    def test_explicit_show_identity_is_not_an_overview_word_match(self):
        candidate = {**self.candidate, 'overview': self.candidate['overview']+' Her friends visit.'}
        self.assertFalse(self.check(query="In Friends Mira breaks Oren's armchair", candidate=candidate)['confirmed'])

    def test_common_single_word_title_does_not_force_show_scope(self):
        required = evidence.constraints('a woman is lost at sea', self.catalog, [self.candidate])
        self.assertEqual(required['titles'], [])

    def test_reversed_actor_rejected_even_if_model_says_entailed(self):
        proof = {**self.proof, 'query_actor': 'Oren'}
        self.assertEqual(self.check(query="Oren breaks Mira's armchair", proof=proof)['reason'], 'actor_identity_mismatch')

    def test_object_owner_cannot_be_invented_as_active_source_agent(self):
        proof = {**self.proof, 'query_actor': 'Oren', 'source_actors': ['Oren']}
        self.assertEqual(self.check(query="Oren breaks Mira's armchair", proof=proof)['reason'], 'unbound_source_actor')

    def test_false_passive_voice_cannot_bypass_subject_order(self):
        proof = {**self.proof, 'query_actor': 'Oren', 'source_actors': ['Oren'], 'source_voice': 'passive'}
        self.assertFalse(self.check(query="Oren breaks Mira's armchair", proof=proof)['confirmed'])

    def test_genuine_passive_voice_agent_is_supported(self):
        candidate = {**self.candidate, 'overview': "Oren's armchair is broken by Mira while Ada watches."}
        proof = {**self.proof, 'evidence': [candidate['overview']], 'source_action': 'broken', 'source_voice': 'passive'}
        self.assertTrue(self.check(candidate=candidate, proof=proof)['confirmed'])

    def test_ownership_only_query_does_not_require_owner_to_be_actor(self):
        proof = {**self.proof, 'actor_relation': 'unspecified', 'query_actor': ''}
        self.assertTrue(self.check(query="The episode with Oren's broken armchair", proof=proof)['confirmed'])

    def test_unknown_detail_cannot_be_confirmed(self):
        proof = {**self.proof, 'unsupported_details': ['The source does not state the location.']}
        self.assertFalse(self.check(query="Mira breaks Oren's armchair in Antarctica", proof=proof)['confirmed'])

    def test_model_contradiction_is_not_confirmed(self):
        self.assertFalse(self.check(proof={**self.proof, 'decision': 'contradicted'})['confirmed'])

    def test_fabricated_or_other_candidate_quote_is_rejected(self):
        self.assertEqual(self.check(proof={**self.proof, 'evidence': ['Oren breaks a dining table.']})['reason'], 'invalid_quote')

    def test_exact_quote_alone_is_insufficient(self):
        self.assertFalse(self.check(proof={'evidence': [self.candidate['overview']]})['confirmed'])

    def test_extra_candidate_id_or_properties_are_rejected(self):
        self.assertFalse(self.check(proof={**self.proof, 'candidate_id': 'some-other-item'})['confirmed'])

    def test_malformed_proof_and_missing_fields_are_rejected(self):
        required = evidence.constraints(self.query, self.catalog, [self.candidate])
        for value in (None, [], 'entailed', {'decision': 'entailed'}):
            with self.subTest(value=value):
                self.assertFalse(evidence.validate(self.query, self.candidate, self.catalog, required, value)['confirmed'])
        proof = copy.deepcopy(self.proof)
        proof['source_actors'] = 'Mira'
        self.assertFalse(self.check(proof=proof)['confirmed'])

    def test_surname_does_not_merge_different_characters(self):
        aliases = evidence.alias_roles(self.catalog, 'Garden Stories')
        self.assertFalse(evidence.same_entity('Mira', 'Oren', aliases))
        self.assertFalse(evidence.same_entity('Mira', 'Vale', aliases))

    def test_unique_cast_role_can_resolve_first_name_and_surname(self):
        aliases = evidence.alias_roles(self.catalog, 'Garden Stories')
        self.assertTrue(evidence.same_entity('Ada', 'Quinn', aliases))
        self.assertFalse(evidence.same_entity('Ada', 'Mira', aliases))

    def test_actor_must_be_bound_to_query_not_hallucinated(self):
        self.assertFalse(self.check(proof={**self.proof, 'query_actor': 'Ada'})['confirmed'])

    def test_actor_conflict_is_rejected_despite_entailed_label(self):
        self.assertFalse(self.check(proof={**self.proof, 'actor_relation': 'conflict'})['confirmed'])

    def consensus(self, proof=None, score=None, query=None):
        query=self.query if query is None else query
        required=evidence.constraints(query,self.catalog,[self.candidate])
        score=score if score is not None else {'available':True,'scores':{'entailment':0.99,'neutral':0.005,'contradiction':0.005}}
        return evidence.consensus(query,self.candidate,self.catalog,required,
                                  self.proof if proof is None else proof,score)

    def test_independent_agreement_supports_candidate(self):
        self.assertTrue(self.consensus()['confirmed'])

    def test_generator_cannot_overrule_neutral_independent_check(self):
        decision=self.consensus(score={'available':True,'scores':{'entailment':0.05,'neutral':0.94,'contradiction':0.01}})
        self.assertFalse(decision['confirmed'])
        self.assertEqual(decision['status'],'possible')

    def test_independent_model_cannot_overrule_actor_conflict_vote(self):
        self.assertFalse(self.consensus(proof={**self.proof,'actor_relation':'conflict'})['confirmed'])

    def test_identity_constraint_overrules_two_positive_models(self):
        decision=self.consensus(query="In Friends Mira breaks Oren's armchair")
        self.assertFalse(decision['confirmed'])
        self.assertEqual(decision['status'],'rejected')

    def test_unavailable_evidence_stays_possible(self):
        self.assertEqual(self.consensus(score={'available':False,'reason':'context_limit'})['status'],'possible')

    def test_invalid_probability_values_fail_closed(self):
        required={'names':[],'titles':[]}
        for scores in ({'entailment':float('nan'),'neutral':0.,'contradiction':0.},
                       {'entailment':1.1,'neutral':-0.1,'contradiction':0.},
                       {'entailment':1.,'neutral':1.,'contradiction':1.}):
            self.assertFalse(entailment.decide(self.query,self.candidate,self.catalog,required,{'available':True,'scores':scores})['confirmed'])

    def test_valid_quote_cannot_override_unstated_detail(self):
        self.assertFalse(self.consensus(proof={**self.proof,'unsupported_details':['Location is unknown.']})['confirmed'])

    def test_malformed_generator_vote_cannot_confirm(self):
        self.assertFalse(self.consensus(proof={'decision':'entailed'})['confirmed'])

    def test_source_aliases_are_canonicalized_without_merging_siblings(self):
        result=entailment.canonicalize('Mira speaks to Oren and Ada.',self.catalog,'Garden Stories')
        self.assertIn('mira vale',result)
        self.assertIn('oren vale',result)
        self.assertIn('ada quinn',result)

    def test_agentless_passive_does_not_support_active_agent(self):
        required={'names':['Mira','Oren'],'titles':[]}
        candidate={**self.candidate,'overview':"They find Mira when she's buried alive under the rubble."}
        self.assertTrue(evidence.active_agent_conflict('Mira buries Oren alive',candidate,required))

    def test_explicit_passive_agent_can_support_active_query(self):
        required={'names':['Mira','Oren'],'titles':[]}
        candidate={**self.candidate,'overview':'Oren is buried by Mira under the rubble.'}
        self.assertFalse(evidence.active_agent_conflict('Mira buries Oren',candidate,required))

    def test_passive_query_is_not_mistaken_for_an_active_agent(self):
        required={'names':['Mira'],'titles':[]}
        candidate={**self.candidate,'overview':'Mira was buried under the rubble.'}
        self.assertFalse(evidence.active_agent_conflict('Mira is buried under rubble',candidate,required))

    def test_extra_condition_requires_separate_evidence(self):
        decision=self.consensus(query="Mira breaks Oren's armchair before the evidence expires")
        self.assertFalse(decision['confirmed'])
        self.assertEqual(decision['reason'],'additional_claim_not_supported')

    def test_coordinated_names_are_not_separate_event_claims(self):
        self.assertEqual(evidence.dependent_claims('Mira and Oren go fishing'),[])

    def test_completed_secondary_claims_are_enumerated(self):
        self.assertEqual(evidence.dependent_claims('Mira finds a letter while Oren repairs a bicycle'),['Oren repairs a bicycle'])

    def test_unsupported_deadline_clause_cannot_be_overruled(self):
        query="Mira breaks Oren's armchair before the evidence expires"
        scores={'available':True,'scores':{'entailment':0.99,'neutral':0.005,'contradiction':0.005},
                'dependent_claims':[{'claim':'the evidence expires','result':{'available':True,'scores':{'entailment':0.05,'neutral':0.94,'contradiction':0.01}}}]}
        self.assertFalse(self.consensus(query=query,score=scores)['confirmed'])


if __name__ == '__main__':
    unittest.main()
