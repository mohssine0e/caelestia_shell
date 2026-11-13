# Assistant context and intelligence

**Judgment:** your complaint about unrelated Java/Bash content has a concrete cause. “Personal on” enables several broad context sources together. The assistant should personalize **only where it helps the current request**.

The saved developer profile contains Java and Bash references; the learner profile contains Java references. Their private contents are intentionally omitted here. The code then injects these sources without checking the question's subject. This is a strong explanation for the reported behavior, not proof of which source caused every past answer.

## Current → proposed

| ID / priority | Current evidence | Needed change |
|---|---|---|
| A01 · P1 | **Confirmed:** profile, learner profile, and workspace are all added whenever personal context is enabled. The workspace explicitly tells the model to tailor the answer to the project/file/technology. [API:781](../../scripts/assistant_api.py#L781), [API:412](../../scripts/assistant_api.py#L412) | Build one context selector. Require a relevance reason for every optional source. General questions must work with no personal context. |
| A02 · P1 | **Confirmed:** learner injection includes weak domains and several blindspots on every eligible request; profile defaults include Bash. [API:304](../../scripts/assistant_api.py#L304), [API:334](../../scripts/assistant_api.py#L334) | Separate communication preferences from technical background and practice feedback. Send only topic-matching technical facts; use practice feedback in learning sessions or a directly relevant explanation. |
| A03 · P1 | **Confirmed:** `runAction` defaults source text to the current selection, including unrelated Ask requests. Workspace is guessed from the most recently focused non-shell client and process working directory. [Assistant:1320](../../services/Assistant.qml#L1320), [API:375](../../scripts/assistant_api.py#L375) | Treat selection as an explicit attachment with a visible include/remove state. Capture source app at invocation; do not represent an app's working directory as verified project context. Require relevance or an explicit project choice. |
| A04 · P1 | **Reproduced offline:** Auto topic detection keeps the coffee thread for “What is Java?” and the QML thread for an unrelated Arabic question. Short questions and non-ASCII tokenization are major blind spots. [Assistant:377](../../services/Assistant.qml#L377) | Use Unicode-aware intent/topic checks. Explicit mode still wins. Start a separate topic when clearly unrelated; preserve pronoun-based follow-ups; ask one focused question only when ambiguity matters. |
| A05 · P2 | **Confirmed:** memory ranking uses substring matches and a score threshold of 2; project cards require the entire title/topic/path label to appear in the question. [Memory:368](../../services/Memory.qml#L368) | Use normalized terms/entities, topic and project identity, freshness, and a minimum relevance threshold. Return zero cards when none qualify. Match project ID/path separately from display titles. |
| A06 · P2 | **Confirmed:** QML retains only three question/answer pairs and compresses answers to roughly 650–750 characters; Python separately allows twelve messages. [Assistant:333](../../services/Assistant.qml#L333), [API:734](../../scripts/assistant_api.py#L734) | Define one conversation budget. Keep recent exact turns and a compact topic summary preserving decisions, constraints, and referenced code. Do not discard details needed by “the second example.” |
| A07 · P1 | **Confirmed:** recalled answers, memory rules, learner statements, and app titles are assembled into instruction-like text. Gemini also embeds instructions into ordinary content. [API:743](../../scripts/assistant_api.py#L743), [API:803](../../scripts/assistant_api.py#L803), [API:172](../../scripts/assistant_api.py#L172) | Separate trusted behavior instructions from quoted, untrusted source data. Use each provider's supported system-instruction channel. Source material must not gain authority over the user's question. |
| A08 · P2 | **Confirmed:** adaptive length instructions already exist, but profile “concise” defaults and fixed language/action templates can compete. `max_chars` bounds selection, not the whole request. [API:34](../../scripts/assistant_api.py#L34), [API:71](../../scripts/assistant_api.py#L71), [API:717](../../scripts/assistant_api.py#L717) | Give explicit user length/language requests priority; choose response depth from the task. Budget the complete request, including thread, profile and retrieval, with reserved answer space. |
| A09 · P2 | **Confirmed:** a topic divider is converted into a normal user message when chats are saved, because its `type` is dropped and absent role defaults to user. Reloading a chat can reintroduce older topics. [Assistant:918](../../services/Assistant.qml#L918), [Assistant:839](../../services/Assistant.qml#L839) | Persist message type and topic ID. Reconstruct only the active topic's conversation. UI divider labels are never model messages. |

## Proposed context policy

Start with inexpensive local selection. An extra model call for every question would add cost and delay; only consider one later if measured relevance remains poor.

| Request | Include by default | Include only when relevant or explicitly attached | Leave out |
|---|---|---|---|
| Greeting or simple factual question | Current question, explicit language/format request | Recent thread if clearly a follow-up | Tech stack, workspace, learning weaknesses, unrelated memory/history |
| Translate/rephrase/summarize | Selected attachment and action instructions | User's chosen target language/tone | Developer profile, current editor/project, unrelated conversation |
| Follow-up in the same topic | Current question and relevant recent topic turns | The source previously attached to that topic | Other conversations and unrelated projects |
| Debug/explain code | Question and attached code/error | Matching language/tool versions, verified project context, matching saved conventions | Every other language the user knows |
| Personal planning | Question and relevant constraints | Approved goals/preferences directly connected to the plan | IDE title, git branch, programming weaknesses |
| Practice | Chosen subject and practice state | Relevant mistakes and progress for that subject | Unrelated learner domains and raw history |

Each selected item should internally carry `source`, `reason`, `topic/project`, `timestamp`, and `size`. Return this manifest to the HUD for a small **“Context used”** detail view. Do not introduce a confirmation modal before every message.

Provider adapters should use the relevant API's dedicated instruction support; Gemini documents system instructions separately from conversation content. Verify the exact schema for the endpoint being retained during implementation. [Gemini text-generation documentation](https://aistudio.google.com/docs/text-generation)

Suggested initial limits, to tune with evaluation: at most three relevant memory items; a modest optional-context token allowance; selected documents and recent conversation receive the larger budget when the task needs them. A small number of cards is not a size limit unless each excerpt is bounded too.

“Personal off” should exclude optional profile/workspace/memory/history retrieval. Current-topic conversation and explicitly attached text have their own visible state. Privacy for storage and background jobs is specified in [09](09-privacy-and-security.md); this toggle must not imply more protection than it provides.

## Behavior examples / acceptance tests

| Input and setup | Expected behavior |
|---|---|
| “Hi” while VS Code and a Java project are open | Brief greeting; no project or programming summary. |
| “Translate this email into French” | Translation of attached email; no Java/Bash guidance or forced Arabic output. |
| “What is Java?” after coffee discussion | Answer the new topic; ignore coffee context. |
| “Explain it more clearly” after a QML answer | Keep the QML context and expand only what is useful. |
| Arabic question about coffee after code discussion | Recognize the topic change despite script/language change. |
| “Fix this Bash error” plus attached error | Use Bash and relevant system details; no unrelated Java material. |
| “Give me a detailed comparison…” | Adequate detail, comparisons and reasoning; no arbitrary short-answer template. |
| “Have I sent you the PDF?” with no attachment inventory | State what is actually accessible; ask for the document if needed. Never infer file access from history or a window title. |

The offline check extracted the actual QML `isTopicShift` function and ran four synthetic cases with Node; it made no provider calls. It confirmed the two failures in A04 and correctly preserved “Explain it more clearly” while recognizing a longer English topic change.

**Files:** `services/Assistant.qml`, `services/Memory.qml`, `scripts/assistant_api.py`, `scripts/assistant_common.py`, `scripts/memory_engine.py`; introduce one testable context-builder module only when implementing. HUD changes should expose the selected context without crowding the main view.
