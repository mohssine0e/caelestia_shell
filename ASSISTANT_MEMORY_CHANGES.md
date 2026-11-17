# Assistant adaptive memory: what changed on this branch

Branch: `feat/assistant` (the existing assistant branch, fast-forwarded to `origin/main` before any edits). `main` was not edited. Lyrics and general shell/dashboard work are not part of this branch. No keyboard shortcuts were added.

## Applied (committed)

1. **Facts store**: `scripts/user_facts.py`
   - New file `~/.config/caelestia/user_facts.json`, kept apart from technical memory (`assistant_memory.json` is unchanged).
   - Only this module writes the file. Each write takes a lock, checks the revision the caller saw, and replaces the file atomically with mode 0600.
   - A file that can't be read is never overwritten. The `recover` command keeps a copy of it, then starts a new file.
   - Each fact has: layer (lasting or changing), status (candidate, approved, rejected or archived), source (manual, import or chat, plus the AI's name and an import batch), confidence, review date, sensitive flag, pinned flag, use-in-replies flag, and conflict/supersede links.
   - It has a command-line interface: list, add, edit, status, confirm, batch_status, delete, settings, import and recover.
2. **Import**: `scripts/facts_import.py`
   - Reads JSON Lines files and does a dry run by default. Accepted lines become candidates only.
   - It rejects bad JSON, unknown categories, text that reads like instructions to a model, secrets and contact details. Sensitive topics are flagged.
   - Duplicates are skipped. When a line disagrees with an approved fact, it is marked as a conflict. Approved facts are never overwritten.
3. **Context builder and provider changes**: `scripts/context_builder.py` and `scripts/assistant_api.py`
   - Each request is sorted by type: technical, career, studies, daily life or general.
   - Only approved facts that fit the request are sent, plus pinned preferences. Facts that are sensitive (unless you opt in), past their review date or set to not be used are left out. There are size limits, and each fact sent carries a reason.
   - When the request names a technology, notes about other technologies are dropped, and the default Python/QML/Bash profile is not sent with it.
   - Profile, quiz results, focused window and past answers are only sent when they fit the request. Translate, TL;DR, rephrase and examples get no personal context.
   - Saved data goes into a labelled JSON block in the user turn. Gemini now uses its real `systemInstruction` field, and Groq's system message holds only rules written in the code. The follow-up topic text moved into the user turn.
   - The general Ask and follow-up prompt is now a mentor for studies, career, technical work and daily life. It doesn't police productivity or present guesses about you as facts.
   - The Explain, Fix, Translate, TL;DR, Rephrase and Examples prompts are unchanged. The Gauntlet code was not touched.
   - The touch on study cards is skipped when Personal is off, and that write is now 0600 and atomic (audit P06). Saving the profile uses the shared 0600 atomic writer.
   - Replies report `context_used`, so the UI can show what was sent.

## In progress (work-in-progress commit, not live-tested)

- `services/UserFacts.qml`: a singleton that runs `user_facts.py`, one command at a time, sending the last revision it saw.
- `modules/assistant/FactsView.qml`: the "About you" screen. It has filters (to review, in use, archived, rejected, all), and lets you approve, reject, edit, archive, delete, confirm a fact is still true, pin, and turn off use in replies. You can add a fact, import a file after checking it first, approve or delete everything from one source, and opt in to sensitive facts.
- `modules/assistant/AssistantHUD.qml`: adds an "About you" button with a dot when facts are waiting, the facts view itself, and a "Used: …" badge whose tooltip lists the facts that were used and why.
- `services/Assistant.qml`: automatic memory extraction no longer runs when Personal is off (audit P01). It stores `contextUsed`.
- **Removed dead UI:** the "AI proposed profile" banner in `ProfileView.qml`, plus `proposedProfile`, `acceptProposedProfile()` and `discardProposedProfile()` in `Assistant.qml`. The reason: nothing ever set `proposedProfile` to anything but empty, so the banner could never appear.

## Checks

- New Python tests: `tests/test_user_facts.py`, `tests/test_facts_import.py`, `tests/test_context_builder.py`, `tests/test_assistant_payload.py`, using synthetic data in a temp folder and a mocked network.
- These suites were run and passed while the store, import and context/provider stages were committed. The output of the last full-suite run, after the QML work, was not kept, so run `python3 -m unittest discover -s tests` again.
- QML was checked statically only:
  - `qmllint` (Qt 6 on Ubuntu) reported no syntax errors in the changed files. It shows many warnings about unresolved Quickshell/Caelestia types, the same as on `main`.
  - The repo's `scripts/qml-lint-conventions.py` reports no violations in the two new QML files.
- The shell was never run, so none of the UI has been tested live.

## Not done

- Learning facts about you automatically from chats is deferred, as the plan recommended.
- The three-writer race on `assistant_memory.json` (audit M02) is not fixed.
- The UI audit and redesign is not done beyond removing the dead banner.
- No live test with Gemini or Groq has been run.
- The filters, JSON labelling and your approval lower the risk of prompt injection. They don't guarantee immunity to it.
