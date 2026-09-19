# Native Qwen and bounded fallback

ARCHi manages local Qwen as its default language engine. Identity, memory,
document ownership, ARC tools, permissions and accepted state remain native app
responsibilities. Qwen itself is a local language model, not a replacement for
these services.

On launch, **ARCHi · Qwen first** checks local readiness without sending a
question. It reuses loopback Ollama or starts the installed runtime with cloud
disabled. Qwen's existing checks still require an installed supported model and
verify its identity before generation. This feature does not install Ollama,
download model weights or bundle them in ARCHi.

## Sending and fallback

Each Send begins with Qwen. A connection, technical generation or timeout failure
can admit **one Codex fallback** through the existing Codex account integration.
Cancellation, changed context, invalid proposals, input limits and storage errors
do not authorize fallback. A failed fallback ends the request; it never retries
or loops between models.

The fallback carries the captured question, explicitly shared document copy,
selected passage, reply settings and companion presentation. It excludes kept
lessons, personal profile context, prior local conversation and incomplete Qwen
output. A captured desktop window requires permission for its exact current copy
before that copy can enter the external route.

The original request identifier, current-context ticket and document target remain
bound to both attempts. Stop, changed source, route or local context invalidates
the work. A revision remains a proposal until the existing checks and explicit
Apply action succeed.

## User choices

- **ARCHi · Qwen first:** managed local startup and one eligible Codex fallback.
- **Local Qwen · auto-connect:** managed local connection, no external fallback.
- **Local Qwen · manual:** explicit local connection, no external fallback.
- **Codex / Compare:** the existing explicit external-reference routes.

The chosen route is saved on this Mac separately from companion identity and
survives restart/profile switching. An unreadable saved choice uses local-only
auto-connect. Automatic preparation never sends a prompt or connects to Codex.

## Accounting and current limits

Usage records one task. Its local lane exists first; the external lane is admitted
only after the eligible local failure has been retained. Accounting failure stops
handoff. Local token metrics remain separate from Codex subscription requests;
unknown external token counts, costs and quota remain unknown. This route is not
a new paid API integration and does not claim to enforce subscription quotas.

Only app-launched runtime children receive a termination signal. Existing Ollama
services remain under their original owner's control. Shutdown requests graceful
termination; it does not force-kill the service. ARC's optional local Qwen proposer uses this same runtime manager. Local ARC commands still execute
through their native task services without automatically invoking either model.

This is an initial managed-runtime integration. A bundled inference engine,
model installation UI, Claude/Gemini fallback adapters and live cloud fallback
qualification remain separate work. Focused fake-client checks establish routing
and context boundaries, not external model quality or full release readiness.
