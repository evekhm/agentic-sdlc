# Skill: trusted-posting

Discipline for every workflow-driven GitHub write (comment, issue,
review, push). Proven in the predecessor system; violations are the
main way automation leaks credentials or exceeds authority.

## Rules

1. **Vetted steps only.** Post through the repository's posting
   scripts / workflow steps, never ad-hoc API calls composed inline.
   The trusted step owns authentication, escaping, and truncation.
2. **Tokens by NAME.** Credentials reach the step as environment
   variables named for their secret (e.g. `ARGUS_BOT_TOKEN`). Never
   echo a token, write it to a file, pass it in argv, or paste it
   into content. If a token value ever appears in your context,
   treat it as compromised and say so.
3. **Stay inside declared authority.** Your persona's `authority`
   block is the whole of your write surface: comment-only means no
   issues, no pushes; a branch glob means never the default branch.
   If a task seems to require more, stop and hand back — do not
   improvise.
4. **Degrade gracefully.** If the preferred write fails
   (permissions, API), fall down the ladder — full review →
   comment with inline detail → summary comment → issue comment —
   and report which rung you landed on. Never retry by switching
   identities.
5. **The hold label is absolute.** If the issue or PR carries
   `hold`, write nothing and stop.
