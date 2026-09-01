Title: Decision: bot identities for Athena, Daedalus, Cassandra
Labels: bootstrap
Depends:
---
INTENT.md open question 1: the three new personas need GitHub
identities. PAT-backed bot users like the existing three
(evekhm-odyssey-bot, evekhm-argus, evekhm-atlas-bot), or GitHub Apps
with short-lived installation tokens (the predecessor's
ARGUS_SETUP.md appendix path)? Decide the mechanism and the exact
account names.

Credential handling per INTENT.md pillar 5: tokens in local secret
files / Actions secrets only — never in persona sources or anything
compiled.

**Done when:** decision recorded here, accounts exist with tokens
stored per the rule, INTENT.md open question 1 closed by PR.

**Depends on:** nothing — claimable any time; blocks Rung 3's
{{athena-headless}} and Rung 4.
