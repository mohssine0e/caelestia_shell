# Privacy, security, and data safety

**Judgment:** the main privacy problem is inconsistent rules across chat, background AI work, and voice. The primary chat/settings path already uses stdin, and several files have private permissions. Extend those good choices to every path.

This is a source/configuration review, not a penetration test. No credentials were printed, no authentication was bypassed, and no requests were sent to providers during the audit.

## Findings

| ID / priority | Current evidence and actual scope | Needed change |
|---|---|---|
| P01 · P1 | **Confirmed:** “Personal off” excludes optional context from the primary answer, but completed turns still enter history and schedule extraction. Extraction sends new interactions plus a projection of all memory cards. [Assistant:1059](../../services/Assistant.qml#L1059), [Assistant:1268](../../services/Assistant.qml#L1268), [Engine:610](../../scripts/memory_engine.py#L610) | Separate request personalization, local storage, and background processing preferences. Make background extraction opt-in; persist the request's privacy policy with the turn and enforce it in every downstream job. |
| P02 · P1 | **Confirmed:** automatic titles send prompt/answer snippets specifically to Gemini when its key exists, independently of the selected chat provider. Chat fallback can send content to another configured provider. [API:546](../../scripts/assistant_api.py#L546), [API:843](../../scripts/assistant_api.py#L843) | Local titles by default. Have a visible provider/fallback policy that also applies to titles, extraction and practice. A configured key alone is not a per-feature privacy preference. |
| P03 · P1 | **Confirmed:** workspace titles/paths and retrieved content enter instruction-like text; no dedicated trust separation exists in the builder. [API:375](../../scripts/assistant_api.py#L375), [API:781](../../scripts/assistant_api.py#L781) | Enforce relevance and data minimization from [02](02-assistant-context-and-intelligence.md). Quote source data separately from trusted instructions. Test malicious instructions embedded in clipboard/history/memory; do not rely on a single warning sentence. |
| P04 · P1 | **Confirmed code path:** the public unlock shortcut and IPC handler emit the same unlock signal used after PAM success; `LockSurface` responds by eventually setting `locked=false`. There is no PAM check in those public entry points. Access requires a process able to invoke this user's session interface; this is not a demonstrated remote attack. [Lock:51](../../modules/lock/Lock.qml#L51), [LockSurface:32](../../modules/lock/LockSurface.qml#L32) | Review/remove public unauthenticated unlock entry points, or require authenticated authorization. Keep the internal PAM-success transition. This path is also present in the locally available upstream Lock.qml; it is not solely a custom-HUD issue. Validate in a controlled session. |
| P05 · P1 | **Confirmed:** bound voice typing records with predictable `/tmp` paths and logs recognized text to `/tmp/voice_debug.log`; the notification repeats the transcript. TTS uses `edge_tts` and a predictable audio fallback path. [voice_type:5](../../scripts/voice_type.sh#L5), [voice_type:40](../../scripts/voice_type.sh#L40), [TTS:74](../../scripts/assistant_tts.py#L74) | Remove transcript logging by default, use private per-session runtime files, clean them on success/cancel/failure, and avoid transcript notification previews. Make online speech processing visible and provide a clearly labeled local option where supported. |
| P06 · P2 | **Observed:** `assistant_memory.json` was mode 0644, and one historical backup also 0644. The containing Caelestia directory is 0700, which currently prevents traversal by other users; this is not proof that they can read it now. Most other inspected stores were 0600. [API writer:468](../../scripts/assistant_api.py#L468), [Engine writer:241](../../scripts/memory_engine.py#L241) | Make permissions consistently 0600 for originals, temporary files and backups, with a private directory. Preserve them through every replacement/export. Retain only necessary backups under a documented policy. |
| P07 · P2 | **Confirmed:** main requests/settings use stdin, but titles, profile data, quick cards, and TTS still pass content in process arguments. Voice credential loading differs from chat. [Assistant:996](../../services/Assistant.qml#L996), [Assistant:1286](../../services/Assistant.qml#L1286), [Memory:457](../../services/Memory.qml#L457), [Assistant:733](../../services/Assistant.qml#L733) | Extend structured stdin to helpers carrying personal text; use one credential resolver. Explain environment-managed keys that cannot be removed by clearing a saved key. Avoid sensitive data in diagnostics. |
| P08 · P2 | **Confirmed, conditional:** weather's automatic-location fallback calls an HTTP IP-location endpoint when location is not configured. [Weather:42](../../services/Weather.qml#L42) | Prefer a configured city or an explicitly chosen secure location service. Do not assume replacing `http` with `https` works without verifying endpoint support. No claim is made about which location path was active during the audit. |
| P09 · P2 | **Confirmed, limited trust boundary:** VPN stats/ping interpolate a configurable interface name into `sh -c`. This is primarily local configuration hardening; no untrusted remote input path was established. [VPN:228](../../services/VPN.qml#L228) | Use argument arrays/file APIs or a strict interface-name allowlist. Keep intentionally user-configured commands visibly separate from names treated as data. |
| P10 · P2 | **Confirmed:** reading/retrieving memory changes `last_touched`, and Python exposure tracking still runs for Ask with Personal off. [Memory:418](../../services/Memory.qml#L418), [API:778](../../scripts/assistant_api.py#L778) | Keep retrieval side-effect free. Record actual use only after the appropriate request succeeds and its policy allows it, through the coordinated writer. |

## Data lifecycle to define

`edge_tts` uses Microsoft's online speech service, so its normal speech path sends text off-device. This is distinct from its local `espeak-ng` fallback. [edge-tts project documentation](https://github.com/rany2/edge-tts)

| Data | Default proposal | User controls |
|---|---|---|
| Current attachment | Included only when deliberately attached to a request/topic | Inspect, replace, remove |
| Chat/history | Visible local persistence policy | Archive, export, retention, delete, scoped forget |
| Personal preferences | Approved and relevant fields | Edit, disable for replies, remove |
| Knowledge suggestions | Local review queue after explicitly allowed extraction | Inspect source, accept, dismiss |
| Learning feedback | Practice-specific use | Review/correct, reset subject, disable in chat |
| Voice/audio | Private temporary storage with reliable cleanup | Online/local mode, target preview, cancel |
| Backups | Private and recoverable | Inspect metadata, restore, explicit retention cleanup |

An optional **Private session** can be added later, but only once it genuinely disables durable history, titles, extraction, practice updates, and other secondary processing. The UI must still explain that the main question is sent to the selected AI provider. Do not label the existing Personal toggle “private.”

Desktop clipboard history is separately enabled in Hyprland (`wl-paste --watch cliphist store`). Restoring the previous clipboard after voice typing does not erase the transcript from clipboard history. Include that distinction in the voice/clipboard settings. [execs.lua:9](/home/mohssine/.config/hypr/hyprland/execs.lua#L9)

## Acceptance checks

- With optional context off, a captured request manifest contains no profile, learner, workspace, memory or cross-chat recall. Explicit attachments/current-topic turns follow their separate controls.
- With background processing off, completing a turn triggers no title/extraction/practice request. Test with an intercepted/mock transport.
- Provider restrictions are respected by all features and fallback attempts.
- Corrupt-data replacements require recovery; deletion/forget effects are inspectable and use stable source IDs. See [04](04-memory-history-and-profile.md).
- No private text appears in helper argv or normal logs; temporary voice files are private and removed after failure/cancel as well as success.
- All storage writers preserve private modes; concurrent writes cannot overwrite unrelated updates.
- Public lock entry points cannot transition a locked controlled test session to unlocked without successful authentication. Verify password/biometric success still works.

**Files:** assistant/memory services and Python helpers, voice scripts, `modules/lock/{Lock,LockSurface,Pam}.qml`, `services/{Weather,VPN}.qml`, and the relevant Hyprland integration. The lock and display changes should be reviewed/tested separately from cosmetic HUD changes.
