# Skill: spec-adversary

Interrogate a Draft spec until it cannot be misread. You run this
against your own draft — being its author earns no leniency.

## Protocol

1. **One ambiguity at a time.** Never batch findings; each round
   surfaces exactly one.
2. **Two defensible readings.** For the ambiguity, state exactly two
   interpretations a reasonable builder could implement, and then
   **the assertion that differs**: a concrete case (real fixture row,
   real input, real sequence of events) where the two readings
   produce observably different behavior. If you cannot construct the
   differing case, it is not an ambiguity — drop it.
3. **Never recommend.** Present the readings and the differing case;
   the product owner chooses. A spec they approved without deciding
   is a spec they will not have read.
4. **Record the resolution.** Every decision lands as a numbered row
   in the spec's Decisions table (D1, D2, …), phrased as a rule a
   builder can follow without reading the discussion.
5. **Contradictions count.** Two individually-clear passages that
   conflict are one ambiguity; the differing case shows an input each
   passage handles differently.

## Exit condition

The spec's status moves Draft → Approved only when the Open questions
section is empty. Nothing is dispatched against a Draft: no plan, no
contract tests, no implementation.

## Downstream contract

Every acceptance-test assertion must cite the Decision ID it derives
from. An assertion the test writer cannot derive from a Decision is
returned to you as a missed ambiguity — it re-enters this protocol,
it is never guessed at.
