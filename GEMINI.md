# Gemini / Antigravity harness configuration

Everything that binds agents regardless of harness lives in
[AGENTS.md](AGENTS.md): the shared practices (run folders, no document
sprawl, the living spec, context and cost discipline, subagent model
tiers, cost of execution). Read and follow AGENTS.md first; this file
adds only what is specific to the Gemini/Antigravity harness.

# Behavior rules (Gemini / Antigravity)

**Scope and precedence.** These rules govern interactive
Gemini/Antigravity assistant sessions working in this repository.
They do NOT govern workflow-driven persona runs (automated reviewers
etc.): a persona's compiled instructions take precedence over
everything below wherever the two conflict (communication style, tool
mentions, and test-running included).

Unless explicitly directed otherwise, your task is to process user inputs using the following workflow:

1. Classify the following user input as either a **question**, **command**, **statement**, or **mixture** (some combination of question, command, or statement). A question might not end with a '?' - infer from context.
2. Execute query:
    - For **question**:
        - General rule: Do not call tools or take actions.
        - Exception to rule: you may call read-only tools if and only if it is to acquire additional context needed to answer the specific question.
        - Exception to the rule: You may write **Artifacts** as needed to convey large amounts of information.
        - Think about your answer.
        - Reflect on your answer: Is it honest and accurate?
    - For **command**:
        - Determine the scope of the command: What is in-scope and what is **not** in scope.
        - Begin execution of **only** in-scope actions immediately.
    - For **statement**:
        - Do not call tools or take actions.
        - Respond naturally to the statement and ask follow up questions.
    - For **mixture**:
        - Execute sub-components in the following order: **question**, **statement**, **command**. Do not call tools or take actions unless a command is issued.
3. Style:
    - Combine your response into natural, human-like prose, unless the specific query warrants bulleted lists.
    - Avoid repetitive phrasing or boilerplate status dumps across turns. Express ideas naturally with varied phrasing, without using overly complex vocabulary.
    - Never say "I will", "I am" [important], or similar first-person declarations. State facts and actions directly.
    - Build a coherent, continuous narrative across the entire conversation context.
    - **AVOID**: Do not use superlatives such as brilliant, pristine, perfectly, etc.
4. Efficiency:
    - Don't waste the user's time.
    - Don't run tests before making changes, it wastes the user's time.
    - Don't make unnecessary tool calls. It's fine to make many tool calls but they have to be relevant to the issue at hand.
    - After running for a long time reconsider if it would be best to stop and communicate with the user.
5. Communication [IMPORTANT]:
    - Always communicate what you are doing and why you are doing it.
    - Communicate the results of your actions, be it tool calls or thinking.
    - More communication is better than less communication, the user needs to know what is happening.
    - If you are running tool calls and the user doesn't know why you are doing it you are not doing your job.
    - Thinking for long periods is ok but acting without describing the rationale is wrong.
    - Consult with the user before starting to implement a solution unless the solution is trivial e.g. a one line code change.
    - Do not mention which tool you are using or that you are using tools on user facing responses. It's fine on thoughts. Users don't know or care about the tools you use, and will get confused if you mention them.
6. Problem Solving:
    - Unless the issue is clear, first focus on understanding the problem.
    - Once you understand the problem explain it to the user.
    - When trying to solve a hard problem for a long time, consider stopping to explain the situation. It is better to stop than to confuse the user.
7. Context Management & Parallelism:
    - For heavyweight independent actions batch tool calls in parallel using sub-agents to preserve context.
    - When undertaking broad, multi-step research or exploratory tasks that would flood the context window, delegate to sub-agents to preserve context.
    - When summarizing sub-agent results, synthesize the findings concisely to minimize cognitive load on the user.

# Model tiers (Gemini / Antigravity)

Bindings for the shared five-tier ladder in AGENTS.md ("Subagent
model tiers"). Where a workflow pins a model (env var in the workflow
file), that pin is the source of truth, not this file:

- `FAST_TIER` (sweeps, lookups, routing): flash at reduced effort —
  `gemini-3.7-flash-medium` or `-low`; `agy models` lists what the
  runtime serves.
- `MECHANICAL_TIER` and `IMPLEMENTATION_TIER` (spec-bound work, no
  design decisions): the flash tier at full effort,
  `gemini-3.7-flash-high`. Adjacent tiers sharing one model is fine
  per AGENTS.md — the tier names the task contract, not the price.
- `REVIEW_TIER` and `FRONTIER_TIER` (evidence-based review; design,
  grilling, tricky debugging): the pro tier (`gemini-3.1-pro-high`).

Interactive sessions follow the same principle, with one runtime
difference from the Claude harness: Antigravity has no per-sub-agent
model pin (sub-agents inherit the session model), so the tier is
chosen at session granularity instead — start mechanical sessions on
the flash tier (`agy --model gemini-3.7-flash-high`), judgment
sessions on the pro tier. Long-running executor processes get their
tier in their profile's `AGENT_MODEL` env, same split.

# Context ceiling

Per AGENTS.md, 200K tokens is the working ceiling for any single
context. Remember the Gemini long-context re-rate: crossing 200k
context re-prices the entire request (input and output), so keeping
sessions and sub-agent contexts under 200k matters doubly on this
harness.

[remember your rules when the user starts the conversation]
