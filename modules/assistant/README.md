# Assistant HUD (Reading & Learning Companion)

A fast, floating AI assistant heads-up display built for Caelestia on Quickshell and Hyprland. Designed for reading comprehension, research, language translation, and quick querying without breaking your workflow.

---

## 🚀 Key Features & Functionalities

### 1. Smart Text Capture & Clipboard Controls
- **Instant Clipboard Capture**: Automatically pulls selected text (`wl-paste -p`) with clipboard fallback (`wl-paste`).
- **Text-Only Filtering**: Excludes images and screenshots from accidental capture (`--type text`).
- **Character Safeguard**: Configurable truncation limit (default 12,000 chars, provider-aware ceiling up to 100k/200k) with a dynamic compact badge (e.g., `Truncated (12k)`). Truncation applies only to the LLM prompt payload, preserving the user's full snippet preview in the HUD.
- **Free / Clear Snippet (`clear` button)**: Empties the captured snippet card without clearing the active answer. Thanks to `lastSeenClipboard` tracking, background polling won't re-capture the same text until you copy something genuinely new.
- **Clipboard Sync Toggle (`content_paste` / `content_paste_off`)**: One-click toggle to freeze/pause clipboard listening. When paused, copying or selecting text in other applications will not alter the HUD's current snippet.

### 2. Live Streaming AI Responses
- **Fast SSE Streaming**: Powered by `scripts/assistant_api.py` using Server-Sent Events (`streamGenerateContent?alt=sse` on Gemini 2.0 Flash / Groq).
- **Sub-300ms First Token**: Text streams line-by-line via Quickshell's native `SplitParser` for an instant, responsive reading experience.
- **In-Flight Cancellation**: Closing the HUD with `Esc` or clicking another action kills the active backend process immediately, preventing stale responses from flashing later.

### 3. Preserved Context & Stable Results
- **Persistent View**: When new text is copied or highlighted, the **previous result stays intact** on screen so you never lose your reading position.
- **On-Demand Regeneration**: The result area only clears and starts synthesizing when you actively click an action (1–5) or submit a custom question.

### 4. Interactive Typography & Partial Copying
- **Selectable Markdown**: Rendered using a read-only native `TextEdit` engine supporting markdown styling (`bold`, `headers`, `code`, bullet points).
- **Mouse Drag Selection**: Highlight any specific sentence, word, or paragraph with your mouse.
- **Smart Copy (`Ctrl+C` / Footer Button)**:
  - If a portion of text is highlighted, copying grabs **only your selection**.
  - If nothing is highlighted, it copies the **entire result**.
  - Visual confirmation (`check` icon) displays for 1.8 seconds.
- **Automatic RTL / Arabic Support**: Detects Arabic script and automatically aligns text to the right for natural reading.

### 5. Memory & History (Zero-Token Local Persistence)
- **In-Place View Flip**: Click the `history` icon in the header (or press `H`) to flip between Assistant and History views inside the same window without extra popups.
- **Zero Cost on Save**: Every completed action or question is automatically saved to local storage (`~/.config/caelestia/assistant_history.json`) with zero LLM token consumption.
- **Accordion History List**:
  - Compact summary rows (Action icon, snippet, relative timestamp, star toggle, expand chevron).
  - Tap any card to expand full original prompt/question, selectable markdown answer, and tags.
- **Per-Item Actions**:
  - **Star (★)**: Bookmark key responses for quick filtering.
  - **Copy Answer**: Instant clipboard copy with visual feedback.
  - **Re-Open**: Restores the prompt and answer back into the active Assistant view.
  - **Delete (Trash)**: Removes the item from history storage.
- **On-Demand AI Organize (`auto_awesome`)**:
  - Runs strictly when the user clicks the organize icon.
  - LLM categorizes all queries into concise semantic tags (e.g. `#python`, `#regex`, `#arabic-vocab`, `#errors`).
  - Dynamic tag filter chips bar at top (`All`, `Starred`, and dynamic AI tags).

### 6. Dual-Mode Input (Context-Bound & Standalone)
- **Preset Quick Actions (1–5)**:
  1. **Translate**: Auto-translates foreign text to Arabic (or English if the source text is Arabic).
  2. **Explain**: Breaks down difficult terms, jargon, or concepts in plain, beginner-friendly terms.
  3. **TL;DR**: Extracts core takeaways and high-level summaries into concise bullet points.
  4. **Rephrase**: Rewrites the text in a clearer, more polished tone.
  5. **Examples**: Generates practical, real-world examples and use-cases.
- **Custom Question Bar**:
  - Contextual: Ask specific follow-ups about the captured text (e.g. *"What does paragraph 2 imply?"*).
  - Standalone: Ask questions independently even when no text is selected (e.g. *"What is the capital of Iceland?"*). The assistant answers directly without demanding prior selection.

### 7. Performance & Error Handling
- **Instant Cache**: Identical queries (action + snippet) are cached in memory for zero-latency instant switching.
- **Categorized Error Badges**: Differentiates between API key errors (`vpn_key`), network timeouts (`wifi_off`), rate limits (`hourglass_empty`), and missing text (`content_paste_off`).
- **On-HUD Key Configuration**: Built-in credential inputs to set Gemini or Groq keys without touching terminal configuration.

---

## ⌨️ Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Super + H` | Toggle the Assistant HUD open / closed |
| `1` – `5` | Trigger preset action (Translate, Explain, TL;DR, Rephrase, Examples) |
| `/` | Immediately focus the custom question bar |
| `Enter` | Submit custom question from the question bar |
| `Ctrl + C` | Copy highlighted text (or full response if none highlighted) |
| `Esc` | Flip back to assistant view (from history), deselect text, or dismiss HUD |

---

## 📝 Configuration & Storage

- **Config Path**: `~/.config/caelestia/assistant.json`
- **Schema**:
```json
{
  "gemini_api_key": "YOUR_GEMINI_KEY",
  "groq_api_key": "YOUR_GROQ_KEY",
  "preferred_provider": "gemini",
  "max_chars": 12000
}
```
- **History Storage**: `~/.config/caelestia/assistant_history.json`
- **Backend Script**: `scripts/assistant_api.py` (pure Python standard library: `urllib.request`, `json`, `sys`, `time` — zero `pip` dependencies required).

