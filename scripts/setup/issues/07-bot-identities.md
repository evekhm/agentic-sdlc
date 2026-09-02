Title: Decision: bot identities for Athena, Daedalus, Cassandra
Labels: bootstrap
Depends:
---
INTENT.md open question 1: the three new personas need GitHub
identities. PAT-backed bot users like the existing three carry-overs,
or GitHub Apps with short-lived installation tokens (the
predecessor's ARGUS_SETUP.md appendix path)? Decide the mechanism and
the exact account names.

**RESOLVED, scope expanded, DONE** (see issue comments for the full
record): GitHub Apps for all six personas, one App per persona, no
PAT bot users — including migrating the three existing carry-overs
(Odyssey, Argus, Atlas) off their PAT accounts. Final names all use
an `-app` suffix (`evekhm-athena-app[bot]`, `evekhm-daedalus-app[bot]`,
`evekhm-cassandra-app[bot]`, `evekhm-odyssey-app[bot]`,
`evekhm-argus-app[bot]`, `evekhm-atlas-app[bot]`) rather than `-bot`,
since App slugs and GitHub usernames share one namespace and could
otherwise collide with an existing account; `-app` was applied
uniformly to all six for consistency. Names/descriptions/permissions/
webhook events per persona, the token-minting mechanism
(`scripts/auth/mint_app_token.py`, `personas/schema.json`
`authority.app_id`/`installation_id`/`token`), and the exact
registration procedure (`scripts/auth/create_all_apps.py`) are
recorded in the issue comments.

Credential handling per INTENT.md pillar 5: tokens in local secret
files / Actions secrets only — never in persona sources or anything
compiled.

**Done when:** decision recorded here (done), all six Apps registered
and installed with `app_id`/`installation_id` filled into
`personas/*.yaml` and private keys stored per the rule (done),
INTENT.md open question 1 closed by PR (done).

**Depends on:** nothing — claimable any time; blocks Rung 3's Athena
intake automation and Rung 4 (Cassandra).
