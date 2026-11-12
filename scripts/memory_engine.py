#!/usr/bin/env python3
"""
scripts/memory_engine.py
Caelestia HUD Assistant - Memory, Knowledge Mastery & Trial Engine.
Strictly decoupled: Pure Python 3 standard library.
"""

import sys
import os
import json
import ast
import re
import time
import shutil
import urllib.request
import urllib.error
from datetime import datetime, timezone, timedelta

from assistant_common import (
    CONFIG_PATH, HISTORY_PATH, MEMORY_PATH, PROFILE_PATH, LEARNER_PROFILE_PATH,
    GEMINI_CANDIDATE_MODELS, GROQ_CANDIDATE_MODELS, STOP_WORDS,
    CODE_TOKEN_PATTERN, WORD_PATTERN, JSON_CLEAN_PATTERN,
    emit, load_config, load_profile, load_learner_profile, save_learner_profile,
    extract_keywords, extract_code_tokens, normalize_concept_key,
    clean_json_response, parse_json_safely, atomic_write_json
)

PROPOSALS_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory_proposals.json")

DEMOTION_THRESHOLD_SECONDS = 30 * 86400  # 30-day mastery decay

# ---------------------------------------------------------
# Learner Profile Subsystem
# ---------------------------------------------------------
def sync_learner_profile(cards=None):
    if cards is None:
        cards = load_memory()
    profile = load_learner_profile()

    # 1. Pull active context from ContextAnchor
    ctx_card = next((c for c in cards if c.get("type") == "context"), None)
    if ctx_card:
        proj = ctx_card.get("project_path") or "active workspace"
        branch = ctx_card.get("git_branch", "main")
        profile["active_context"] = f"{proj} (branch: {branch})"
    elif not profile.get("active_context") or profile.get("active_context") == "unknown workspace":
        profile["active_context"] = "default workspace"

    # 2. Track strongest/weakest domains based on Gauntlet/mastery scores
    domain_scores = {}
    domain_counts = {}
    for c in cards:
        if c.get("type") == "context":
            continue
        dom = c.get("domain") or c.get("category") or "general"
        score = float(c.get("srs_data", {}).get("score", c.get("mastery_score", 0.0)))
        domain_scores[dom] = domain_scores.get(dom, 0.0) + score
        domain_counts[dom] = domain_counts.get(dom, 0) + 1

    avg_scores = {}
    for d, total in domain_scores.items():
        cnt = domain_counts.get(d, 1)
        avg_scores[d] = round(total / cnt, 2)
    profile["domain_scores"] = avg_scores

    sorted_domains = sorted(avg_scores.items(), key=lambda x: x[1])
    profile["weakest_domains"] = [d[0] for d in sorted_domains if d[1] < 0.70][:3]
    profile["strongest_domains"] = [d[0] for d in reversed(sorted_domains) if d[1] >= 0.70][:3]

    # Prepopulate blindspots array from existing traps if empty
    if not profile.get("blindspots"):
        existing_traps = []
        for c in cards:
            dom = c.get("domain") or c.get("category") or "general"
            for t in (c.get("user_traps") or c.get("personal_traps") or []):
                if t and len(t) > 10:
                    existing_traps.append(f"{dom} ({c.get('title') or c.get('topic')}): {t}")
        profile["blindspots"] = existing_traps[:6]

    profile["last_updated"] = datetime.now(timezone.utc).isoformat()
    save_learner_profile(profile)
    return profile

def hook_gauntlet_result(card, resp_data, cards):
    """Gauntlet Hook: updates learner_profile.json when a user fails a Gauntlet tier."""
    try:
        profile = load_learner_profile()
        score = float(resp_data.get("score", 0.0))
        verdict = resp_data.get("verdict", "fail").lower()
        title = card.get("title") or card.get("topic") or "Concept"
        domain = card.get("domain") or card.get("category") or "General"

        new_blindspots = []
        q_results = resp_data.get("q_results", {})

        tier_names = {
            "q1": "Tier 1 (Mental Model)",
            "q2": "Tier 2 (Bug Hunt & Invariants)",
            "q3": "Tier 3 (Edge Case & Traps)"
        }

        # Identify tier-level failures
        for q_id, q_val in q_results.items():
            if isinstance(q_val, dict) and q_val.get("verdict") == "fail":
                tier_label = tier_names.get(q_id, f"Tier {q_id}")
                comment = (q_val.get("comment") or "").strip()
                if not comment:
                    comment = (resp_data.get("personal_trap") or resp_data.get("blindspots") or "Incorrect analysis").strip()
                new_blindspots.append(f"Fails {tier_label} on {domain} ({title}): {comment}")

        # If overall failure without explicit q_results fail
        if (verdict != "pass" or score < 0.85) and not new_blindspots:
            trap = (resp_data.get("personal_trap") or resp_data.get("blindspots") or "Unresolved misconception").strip()
            new_blindspots.append(f"Fails Gauntlet on {domain} ({title}): {trap}")

        current_blindspots = profile.get("blindspots", [])
        for bs in new_blindspots:
            if bs and not any(bs.lower() == existing.lower() for existing in current_blindspots):
                current_blindspots.insert(0, bs)

        profile["blindspots"] = current_blindspots[:10]
        save_learner_profile(profile)
        # Resync domain scores and context
        sync_learner_profile(cards)
    except Exception as e:
        sys.stderr.write(f"[MemoryEngine] hook_gauntlet_result error: {e}\n")

def load_memory(auto_demote=True):
    if not os.path.exists(MEMORY_PATH):
        return []
    try:
        with open(MEMORY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
            if isinstance(data, list):
                now_epoch = time.time()
                mutated = False
                # Normalize schema fields & evaluate 30-day decay
                for card in data:
                    if not isinstance(card, dict):
                        continue

                    # 1. Determine entity type: "knowledge" | "fact" | "context"
                    ctype = card.get("type")
                    if not ctype or ctype not in ["knowledge", "fact", "context"]:
                        if card.get("project_path"):
                            ctype = "context"
                        elif card.get("front") or card.get("tier") == "primitive":
                            ctype = "fact"
                        else:
                            ctype = "knowledge"
                    card["type"] = ctype

                    if ctype == "context":
                        if "domain" not in card:
                            card["domain"] = "workspace"
                        if "title" not in card:
                            card["title"] = card.get("topic") or "Active Workspace"
                        continue

                    # Common status & review fields
                    if "status" not in card:
                        card["status"] = "learning"
                    if "mastery_score" not in card:
                        card["mastery_score"] = 1.0 if card.get("status") == "mastered" else 0.0
                    if "last_reviewed" not in card:
                        card["last_reviewed"] = card.get("updated") or card.get("created") or ""

                    # Normalize SRS Data
                    srs = card.get("srs", {})
                    srs_data = card.get("srs_data", {})
                    score = float(srs_data.get("score") or srs.get("score") or card.get("mastery_score") or 0.0)
                    streak = int(srs_data.get("streak") or srs.get("streak") or 0)
                    interval_days = int(srs_data.get("interval_days") or srs.get("interval_days") or (14 if ctype == "knowledge" else 7))
                    next_rev = srs_data.get("next_review") or srs.get("next_review") or card.get("next_review") or ""

                    card["srs_data"] = {
                        "score": score,
                        "streak": streak,
                        "interval_days": interval_days,
                        "next_review": next_rev,
                        "last_reviewed": card.get("last_reviewed") or card.get("updated") or ""
                    }
                    card["srs"] = card["srs_data"]
                    card["next_review"] = next_rev

                    if ctype == "fact":
                        if "front" not in card:
                            card["front"] = card.get("title") or card.get("topic") or ""
                        if "back" not in card:
                            card["back"] = " ".join(card.get("lines", []))
                        if "title" not in card:
                            card["title"] = card.get("front")
                        card["topic"] = card.get("title")
                        card["lines"] = [card.get("back", "")]
                    else:  # knowledge
                        if "title" not in card:
                            card["title"] = card.get("topic") or "Knowledge Concept"
                        card["topic"] = card.get("title")
                        if "invariants" not in card:
                            card["invariants"] = card.get("lines", [])
                        card["lines"] = card.get("invariants", [])
                        if "user_traps" not in card:
                            card["user_traps"] = card.get("personal_traps") or card.get("traps") or []
                        card["personal_traps"] = card.get("user_traps", [])
                        card["traps"] = card.get("user_traps", [])
                        if "mental_model" not in card:
                            card["mental_model"] = card.get("primer", {}).get("mental_model") or card.get("summary") or card["title"]
                        card["summary"] = card.get("mental_model", "")
                        if "snippet" not in card:
                            card["snippet"] = card.get("primer", {}).get("snippet") or (card.get("sections") and card["sections"][0].get("snippet")) or ""

                    if "category" not in card:
                        card["category"] = "general"
                    if "domain" not in card:
                        card["domain"] = card.get("primer", {}).get("domain") or card.get("category") or "code"
                    if "relations" not in card or not isinstance(card["relations"], list):
                        card["relations"] = []

                    # Spaced Repetition: 30-day decay demotion check for knowledge nodes
                    if auto_demote and ctype == "knowledge" and card.get("status") == "mastered":
                        lr_str = card.get("last_reviewed") or card.get("updated") or card.get("created") or ""
                        if lr_str:
                            try:
                                lr_dt = datetime.fromisoformat(lr_str.replace("Z", "+00:00"))
                                if (now_epoch - lr_dt.timestamp()) > DEMOTION_THRESHOLD_SECONDS:
                                    card["status"] = "learning"
                                    card["mastery_score"] = 0.65
                                    card["last_fail_feedback"] = "Decay: Unreviewed for over 30 days. Re-test to reaffirm mastery."
                                    mutated = True
                            except Exception:
                                pass

                if mutated and auto_demote:
                    atomic_save_memory(data)

                return data
    except Exception:
        pass
    return []

def atomic_save_memory(cards):
    os.makedirs(os.path.dirname(MEMORY_PATH), exist_ok=True)
    tmp_path = MEMORY_PATH + ".tmp"
    bak_path = MEMORY_PATH + ".bak"

    try:
        # Create backup if original exists
        if os.path.exists(MEMORY_PATH):
            try:
                with open(MEMORY_PATH, "r", encoding="utf-8") as src, open(bak_path, "w", encoding="utf-8") as dst:
                    dst.write(src.read())
            except Exception:
                pass

        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(cards, f, indent=2, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())

        os.replace(tmp_path, MEMORY_PATH)
        try:
            os.chmod(MEMORY_PATH, 0o600)
        except Exception:
            pass
        return True
    except Exception as e:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except Exception:
                pass
        raise e

def inspect_memory_file():
    """Validate the memory store and preserve unreadable contents before any replacement."""
    if not os.path.exists(MEMORY_PATH):
        emit({"status": "ok"})
        return
    try:
        with open(MEMORY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list) and all(isinstance(card, dict) for card in data):
            emit({"status": "ok"})
            return
    except Exception:
        pass

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_path = f"{MEMORY_PATH}.corrupt.{stamp}"
    suffix = 1
    while os.path.exists(backup_path):
        backup_path = f"{MEMORY_PATH}.corrupt.{stamp}.{suffix}"
        suffix += 1
    try:
        os.makedirs(os.path.dirname(MEMORY_PATH), mode=0o700, exist_ok=True)
        shutil.copy2(MEMORY_PATH, backup_path)
        os.chmod(backup_path, 0o600)
        emit({"status": "corrupt", "backup_path": backup_path})
    except Exception as e:
        emit({"status": "backup_failed", "error": str(e)})

# ---------------------------------------------------------
# AI Calling Helper (Groq / Gemini Hybrid)
# Fast Groq prioritized to save Gemini quota, with rock-solid fallback
# ---------------------------------------------------------
def call_llm(system_instruction, user_payload, expect_json=True, temperature=0.2):
    config = load_config()
    gemini_key = config.get("gemini_key", "").strip()
    groq_key = config.get("groq_key", "").strip()

    # Prioritize Groq for background memory operations to avoid exhausting Gemini quota
    providers = []
    if groq_key:
        providers.append(("groq", groq_key))
    if gemini_key:
        providers.append(("gemini", gemini_key))

    if not providers:
        raise RuntimeError("No API key available. Configure GEMINI_API_KEY or GROQ_API_KEY.")

    last_error = None
    for prov_name, key in providers:
        try:
            if prov_name == "groq":
                for model_name in GROQ_CANDIDATE_MODELS:
                    url = "https://api.groq.com/openai/v1/chat/completions"
                    messages = [
                        {"role": "system", "content": system_instruction},
                        {"role": "user", "content": user_payload}
                    ]
                    req_dict = {
                        "model": model_name,
                        "messages": messages,
                        "temperature": temperature
                    }
                    if expect_json:
                        req_dict["response_format"] = {"type": "json_object"}
                    
                    req_data = json.dumps(req_dict).encode("utf-8")
                    req = urllib.request.Request(url, data=req_data, headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {key}",
                        "User-Agent": "Mozilla/5.0"
                    }, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=25) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                            choices = data.get("choices", [])
                            if choices:
                                content = (choices[0].get("message", {}).get("content") or "").strip()
                                if content:
                                    return content
                    except Exception as e:
                        last_error = e
                        continue
            elif prov_name == "gemini":
                for model_name in GEMINI_CANDIDATE_MODELS:
                    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model_name}:generateContent?key={key}"
                    gen_config = {"temperature": temperature}
                    if expect_json:
                        gen_config["responseMimeType"] = "application/json"
                    
                    req_data = json.dumps({
                        "contents": [{
                            "parts": [{"text": f"SYSTEM INSTRUCTIONS:\n{system_instruction}\n\nUSER DATA / QUERY:\n{user_payload}"}]
                        }],
                        "generationConfig": gen_config
                    }).encode("utf-8")

                    req = urllib.request.Request(url, data=req_data, headers={"Content-Type": "application/json"}, method="POST")
                    try:
                        with urllib.request.urlopen(req, timeout=30) as resp:
                            data = json.loads(resp.read().decode("utf-8"))
                            candidates = data.get("candidates", [])
                            if candidates:
                                parts = candidates[0].get("content", {}).get("parts", [])
                                if parts:
                                    content = (parts[0].get("text") or "").strip()
                                    if content:
                                        return content
                    except Exception as e:
                        last_error = e
                        continue
        except Exception as e:
            last_error = e
            continue

    raise RuntimeError(f"All AI providers failed: {last_error}")

# ---------------------------------------------------------
# CLI Command: get_context <query>
# Zero-token local matching against assistant_memory.json
# ---------------------------------------------------------
def get_context(query_text):
    cards = load_memory()
    if not cards or not query_text or len(query_text.strip()) < 3:
        emit({"matched": False, "cards": [], "card_ids": [], "prompt_injection": ""})
        return

    q_clean = query_text.strip()
    q_code = extract_code_tokens(q_clean)
    q_words = extract_keywords(q_clean)

    scored = []
    for card in cards:
        topic = (card.get("topic") or "").strip()
        tags = card.get("tags") or []
        lines = card.get("lines") or []

        topic_words = extract_keywords(topic)
        tag_words = extract_keywords(" ".join(tags))
        lines_words = extract_keywords(" ".join(lines[:4]))
        all_card_words = topic_words.union(tag_words).union(lines_words)

        card_code = extract_code_tokens(f"{topic} {' '.join(lines[:3])}")
        shared_code = q_code.intersection(card_code)
        shared_topic = q_words.intersection(topic_words)
        shared_tags = q_words.intersection(tag_words)
        shared_all = q_words.intersection(all_card_words)
        query_coverage = len(shared_all) / len(q_words) if q_words else 0.0

        score = 0.0
        if len(shared_code) >= 2:
            score += 1.5 + (len(shared_code) * 0.4)
        elif len(shared_code) == 1:
            score += 0.8

        score += len(shared_topic) * 0.7
        score += len(shared_tags) * 0.4
        score += query_coverage * 0.9

        if score >= 0.5:
            scored.append((score, card))

    scored.sort(key=lambda x: x[0], reverse=True)
    matched_cards = [c for _, c in scored[:2]]

    if not matched_cards:
        emit({"matched": False, "cards": [], "card_ids": [], "prompt_injection": ""})
        return

    injection_parts = []
    for c in matched_cards:
        status = c.get("status", "learning").upper()
        topic = c.get("topic", "")
        summary = c.get("lines", [""])[0] if c.get("lines") else ""

        is_code = True
        primer = c.get("primer") or {}
        if primer.get("domain") in ("protocol", "conceptual"):
            is_code = False
        elif c.get("category") in ("general", "health", "lifestyle", "productivity", "translation") and not extract_code_tokens(f"{topic} {summary}"):
            is_code = False

        if status == "MASTERED":
            if is_code:
                injection_parts.append(
                    f"[Mastery Grounding: User has MASTERED '{topic}'. Root principle: '{summary}'. Skip introductory basics; provide concise, advanced code.]"
                )
            else:
                injection_parts.append(
                    f"[Mastery Grounding: User has MASTERED '{topic}'. Root principle: '{summary}'. Skip introductory basics; provide clear, actionable principles and protocols (avoid forcing dummy code snippets).]"
                )
        else:
            if is_code:
                injection_parts.append(
                    f"[Learning Grounding: User is LEARNING '{topic}'. Active concept: '{summary}'. Provide an intuitive breakdown with clear steps and code.]"
                )
            else:
                injection_parts.append(
                    f"[Learning Grounding: User is LEARNING '{topic}'. Active concept: '{summary}'. Provide an intuitive breakdown with clear actionable guidelines.]"
                )

    emit({
        "matched": True,
        "cards": [
            {
                "id": c.get("id"),
                "topic": c.get("topic"),
                "status": c.get("status"),
                "summary": c.get("lines", [""])[0] if c.get("lines") else ""
            } for c in matched_cards
        ],
        "card_ids": [str(c.get("id")) for c in matched_cards if c.get("id")],
        "prompt_injection": " ".join(injection_parts)
    })

# ---------------------------------------------------------
# CLI Command: distill
# Thread-aware, noise-filtered memory card distillation
# ---------------------------------------------------------
DISTILL_PROMPT = """You are a strict knowledge classifier. Analyze the chat history and propose durable technical knowledge only.

Do not create cards for personal preferences, response style, identity, or general instructions about how the assistant should behave; those belong in the user's separate Profile settings. For every knowledge/fact card, set scope to 'general' or 'project'. Use 'project' only when the source explicitly concerns a named/path-specific project; include project_path when known. Do not infer a project path.

If it is a DEEP CONCEPT, you MUST extract a Mental Model, at least 2 Invariants, a valid Code Snippet, and at least 1 personal trap. Output as type 'knowledge'.
If it is a QUICK FACT, output only a 1-sentence question and a 1-sentence answer. Output as type 'fact'.
Do not create standalone workspace-context cards. Add project scope to a technical knowledge card only when the conversation contains durable project-specific knowledge.

DO NOT output generic summaries. Output STRICT JSON.

OUTPUT JSON SCHEMA:
{
  "cards": [
    {
      "id": "card_<domain>_<slug>",
      "type": "knowledge",
      "scope": "general|project",
      "domain": "code|concurrency|architecture|networking|linux|general",
      "title": "Clear Concept Title (5-7 words max)",
      "mental_model": "Underlying cause-and-effect principle and WHY it works",
      "invariants": [
        "Universal rule or invariant 1",
        "Universal rule or invariant 2"
      ],
      "snippet": "```lang\\n// Valid production code snippet\\n...\\n```",
      "user_traps": [
        "Specific personal trap or pitfall to avoid"
      ],
      "tags": ["relevant", "tags"],
      "sources": ["source_interaction_id"]
    },
    {
      "id": "fact_<domain>_<slug>",
      "type": "fact",
      "scope": "general|project",
      "domain": "vocab|architecture|linux|general",
      "front": "1-sentence question or prompt?",
      "back": "1-sentence authoritative answer.",
      "tags": ["relevant", "tags"],
      "sources": ["source_interaction_id"]
    }
  ]
}
"""

def distill():
    try:
        with open(PROPOSALS_PATH, "r", encoding="utf-8") as f:
            pending_proposals = json.load(f)
        if not isinstance(pending_proposals, list): pending_proposals = []
    except FileNotFoundError:
        pending_proposals = []
    except Exception:
        emit({"success": False, "error": "Proposal queue is unreadable; preserving it and stopping distillation."})
        return
    if not os.path.exists(HISTORY_PATH):
        emit({"success": True, "new_cards": 0, "updated_cards": 0, "total_cards": 0, "message": "No history file found."})
        return

    try:
        with open(HISTORY_PATH, "r", encoding="utf-8") as f:
            raw_history = json.load(f)
            if not isinstance(raw_history, list):
                raw_history = []
    except Exception:
        raw_history = []

    current_memory = load_memory()
    indexed_sources = set()
    for card in current_memory:
        for s in card.get("sources", []):
            if s:
                indexed_sources.add(str(s))
    for proposal in pending_proposals:
        if isinstance(proposal, dict):
            indexed_sources.update(str(s) for s in proposal.get("sources", []) if s)

    # Filter unindexed, non-noise entries
    unindexed = []
    for item in raw_history:
        if not isinstance(item, dict):
            continue
        iid = str(item.get("id", ""))
        if not iid or iid in indexed_sources or item.get("context_excluded"):
            continue

        prompt = (item.get("prompt") or "").strip()
        text = (item.get("text") or "").strip()
        ans = (item.get("answer") or "").strip()
        
        # Skip pure noise / greetings / trivial checks
        if len(text) < 12 and len(prompt) < 12 and not extract_code_tokens(text + " " + prompt):
            continue
        if item.get("action") == "translate" and len(text) < 30 and not extract_code_tokens(text):
            continue

        unindexed.append({
            "id": iid,
            "prompt": prompt[:300],
            "text": text[:500],
            "answer": ans[:600],
            "action": item.get("action", "ask"),
            "timestamp": item.get("timestamp", 0)
        })

    if not unindexed:
        emit({
            "success": True,
            "new_cards": 0,
            "updated_cards": 0,
            "total_cards": len(current_memory),
            "message": "All history is already indexed."
        })
        return

    # Take up to 40 most recent unindexed entries to prevent token exhaustion
    batch = unindexed[-40:]

    payload = {
        "current_memory": [
            {
                "id": c.get("id"),
                "type": c.get("type", "knowledge"),
                "domain": c.get("domain", "general"),
                "title": c.get("title") or c.get("topic"),
                "mental_model": c.get("mental_model"),
                "invariants": c.get("invariants") or c.get("lines"),
                "front": c.get("front"),
                "back": c.get("back"),
                "tags": c.get("tags"),
                "sources": c.get("sources", [])
            } for c in current_memory
        ],
        "new_interactions": batch
    }

    try:
        raw_resp = call_llm(DISTILL_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        new_cards = resp_data.get("cards", [])
        if not isinstance(new_cards, list):
            new_cards = []
    except Exception as e:
        emit({"success": False, "error": f"Distillation AI call failed: {e}"})
        return

    # Extraction creates reviewable drafts; only explicit user acceptance writes memory cards.
    staged = []
    for nc in new_cards:
        if not isinstance(nc, dict):
            continue
        ctype = nc.get("type", "knowledge")
        if ctype not in ("knowledge", "fact"):
            continue
        scope = "project" if ctype == "context" else (nc.get("scope") if nc.get("scope") in ("general", "project") else "general")
        title = nc.get("title") or nc.get("topic") or nc.get("front") or "Workspace Context"
        sources = list(dict.fromkeys(str(s) for s in nc.get("sources", []) if s))
        if not sources:
            # A model response without source attribution is not safe to add to memory.
            continue
        staged.append({**nc, "id": nc.get("id") or f"proposal_{int(time.time()*1000)}_{len(staged)}",
                       "title": title, "type": ctype, "scope": scope, "review_status": "pending",
                       "sources": sources, "proposed_at": datetime.now(timezone.utc).isoformat()})
    if staged:
        existing_ids = {str(p.get("id")) for p in pending_proposals if isinstance(p, dict)}
        pending_proposals.extend(p for p in staged if str(p["id"]) not in existing_ids)
        atomic_write_json(PROPOSALS_PATH, pending_proposals)
    emit({"success": True, "new_cards": len(staged), "updated_cards": 0, "pending_proposals": len(pending_proposals), "total_cards": len(current_memory),
          "message": "New knowledge is waiting for review." if staged else "No durable knowledge found."})
    return

    now_iso = datetime.now(timezone.utc).isoformat()
    existing_map = {c.get("id"): c for c in current_memory}

    def find_existing_card(card_type, target_id, target_title, project_path=""):
        if target_id and target_id in existing_map:
            return existing_map[target_id]
        if card_type == "context" and project_path:
            norm_target_path = os.path.abspath(project_path).rstrip("/").lower()
            for c in existing_map.values():
                if c.get("type") == "context":
                    c_path = os.path.abspath(c.get("project_path") or "").rstrip("/").lower()
                    if c_path and c_path == norm_target_path:
                        return c
        norm_key = normalize_concept_key(target_title)
        if not norm_key:
            return None
        for c in existing_map.values():
            if c.get("type") != card_type and card_type != "context":
                continue
            c_title = c.get("title") or c.get("topic") or c.get("front") or ""
            c_norm = normalize_concept_key(c_title)
            if not c_norm:
                continue
            if norm_key == c_norm:
                return c
            if len(norm_key) >= 10 and len(c_norm) >= 10:
                if norm_key in c_norm or c_norm in norm_key:
                    return c
        return None

    created_count = 0
    updated_count = 0

    for nc in new_cards:
        if not isinstance(nc, dict):
            continue
        ctype = nc.get("type", "knowledge")
        cid = nc.get("id") or f"{'ctx' if ctype == 'context' else ('fact' if ctype == 'fact' else 'card')}_{int(time.time()*1000)}"

        if ctype == "context":
            ctx_path = nc.get("project_path") or os.getcwd()
            ctx_title = nc.get("title") or ctx_path or "Workspace Context"
            existing_ctx = find_existing_card("context", cid, ctx_title, ctx_path)
            card = {
                "id": existing_ctx.get("id") if existing_ctx else cid,
                "type": "context",
                "domain": "workspace",
                "title": ctx_title,
                "topic": ctx_title,
                "project_path": ctx_path,
                "git_branch": nc.get("git_branch") or "main",
                "last_active": now_iso,
                "_ts": int(time.time() * 1000)
            }
            if existing_ctx:
                existing_ctx.update(card)
                updated_count += 1
            else:
                existing_map[cid] = card
                created_count += 1
            continue

        if ctype == "fact":
            front = nc.get("front") or nc.get("title") or nc.get("topic") or "Quick Fact"
            back = nc.get("back") or " ".join(nc.get("lines", []))
            tags = list(set((nc.get("tags") or [])))
            sources = list(set((nc.get("sources") or [])))
            existing_fact = find_existing_card("fact", cid, front)
            if existing_fact:
                card = existing_fact
                card["type"] = "fact"
                card["front"] = front
                card["back"] = back
                card["title"] = front
                card["topic"] = front
                card["lines"] = [back]
                card["domain"] = nc.get("domain") or card.get("domain", "general")
                card["tags"] = list(set((card.get("tags") or []) + tags))
                card["sources"] = list(set((card.get("sources") or []) + sources))
                card["updated"] = now_iso
                card["_ts"] = int(time.time() * 1000)
                updated_count += 1
            else:
                next_rev = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
                card = {
                    "id": cid,
                    "type": "fact",
                    "domain": nc.get("domain") or "general",
                    "title": front,
                    "topic": front,
                    "front": front,
                    "back": back,
                    "lines": [back],
                    "status": "learning",
                    "mastery_score": 0.0,
                    "srs_data": {
                        "score": 0.0,
                        "streak": 0,
                        "interval_days": 1,
                        "next_review": next_rev,
                        "last_reviewed": now_iso
                    },
                    "srs": {
                        "score": 0.0,
                        "streak": 0,
                        "interval_days": 1,
                        "next_review": next_rev
                    },
                    "next_review": next_rev,
                    "tags": tags,
                    "sources": sources,
                    "created": now_iso,
                    "updated": now_iso,
                    "_ts": int(time.time() * 1000)
                }
                existing_map[cid] = card
                created_count += 1
            continue

        # KnowledgeNode
        title = nc.get("title") or nc.get("topic") or "Knowledge Concept"
        mental_model = nc.get("mental_model") or nc.get("summary") or title
        invariants = nc.get("invariants") or nc.get("lines") or []
        user_traps = nc.get("user_traps") or nc.get("personal_traps") or []
        snippet = nc.get("snippet", "")
        tags = list(set((nc.get("tags") or [])))
        sources = list(set((nc.get("sources") or [])))

        existing_knowledge = find_existing_card("knowledge", cid, title)
        if existing_knowledge:
            card = existing_knowledge
            card["type"] = "knowledge"
            card["title"] = title
            card["topic"] = title
            card["domain"] = nc.get("domain") or card.get("domain", "code")
            card["mental_model"] = mental_model
            card["summary"] = mental_model
            merged_invs = list(dict.fromkeys((card.get("invariants") or card.get("lines") or []) + invariants))
            card["invariants"] = merged_invs
            card["lines"] = merged_invs
            if snippet:
                card["snippet"] = snippet
            if user_traps:
                card["user_traps"] = list(set((card.get("user_traps") or []) + user_traps))
                card["personal_traps"] = card["user_traps"]
            card["tags"] = list(set((card.get("tags") or []) + tags))
            card["sources"] = list(set((card.get("sources") or []) + sources))
            card["updated"] = now_iso
            card["_ts"] = int(time.time() * 1000)
            updated_count += 1
        else:
            next_rev = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
            card = {
                "id": cid,
                "type": "knowledge",
                "domain": nc.get("domain") or "code",
                "title": title,
                "topic": title,
                "mental_model": mental_model,
                "summary": mental_model,
                "invariants": invariants,
                "lines": invariants,
                "snippet": snippet,
                "user_traps": user_traps,
                "personal_traps": user_traps,
                "sections": nc.get("sections", []),
                "primer": {},
                "status": "learning",
                "mastery_score": 0.0,
                "srs_data": {
                    "score": 0.0,
                    "streak": 0,
                    "interval_days": 1,
                    "next_review": next_rev,
                    "last_reviewed": now_iso
                },
                "srs": {
                    "score": 0.0,
                    "streak": 0,
                    "interval_days": 1,
                    "next_review": next_rev
                },
                "next_review": next_rev,
                "tags": tags,
                "sources": sources,
                "created": now_iso,
                "updated": now_iso,
                "_ts": int(time.time() * 1000)
            }
            existing_map[cid] = card
            created_count += 1

    final_cards = list(existing_map.values())
    atomic_save_memory(final_cards)
    sync_learner_profile(final_cards)

    emit({
        "success": True,
        "new_cards": created_count,
        "updated_cards": updated_count,
        "total_cards": len(final_cards)
    })

# ---------------------------------------------------------
# CLI Command: challenge <card_id>
# Adaptive mastery assessment suite scaled to domain & complexity
# ---------------------------------------------------------
CHALLENGE_PROMPT = """You are a senior technical examiner and developer mentor.
Generate an adaptive mastery assessment suite tailored specifically to the card's domain and complexity.

ADAPTIVE ASSESSMENT RULES:
1. COMPLEXITY & QUESTION COUNT:
   - "small" complexity: Return EXACTLY 1 to 2 questions (e.g. 1 focused QCM + 1 quick scenario check). Do NOT overwhelm small concepts with unnecessary questions.
   - "medium" complexity: Return EXACTLY 2 to 3 questions (e.g. 1 QCM + 1 bug hunt/scenario check + 1 edge case).
   - "deep" complexity: Return 3 to 4 questions (e.g. 1 QCM + 1-2 diagnosis/bug hunts + 1 edge case / trade-off).

2. DOMAIN-SPECIFIC QUESTION TYPES:
   - For "code" domain:
     - 'qcm': Multiple choice on syntax invariants, lifecycle, or timing. 4 options (A, B, C, D) with one unambiguous answer.
     - 'bug_hunt': Markdown code snippet or shell pipeline containing a subtle bug, race condition, or memory leak. Ask where the bug is and how to fix it.
     - 'edge_case': Architectural or boundary failure scenario under extreme conditions.
   - For "protocol" / non-code domain:
     - 'qcm': Multiple choice on core principles, trade-offs, or physiological/operational mechanisms.
     - 'bug_hunt' (or scenario diagnosis): A realistic real-world protocol execution scenario where someone applied the concept incorrectly or under suboptimal conditions. Ask to identify what went wrong and how to correct the protocol. DO NOT USE FAKE CODE SNIPPETS.
     - 'edge_case': What fails under extreme conditions (e.g. severe sleep deficit, high stress, boundary constraints) and why.

3. TARGETED WEAKNESS & PERSONAL TRAP FOCUS:
   - If 'personal_traps' contains items, AT LEAST ONE question (e.g. q1 or a diagnosis scenario) MUST specifically target and test whether the user has overcome their documented personal traps: {personal_traps}. Probe them deliberately on their past mistakes!
   - If 'last_fail_feedback' is present and non-empty, directly probe and diagnose the exact pitfall or misconception described to verify that the user has corrected their understanding.

FORMAT REQUIREMENT:
Return valid JSON with:
{
  "card_id": "<card_id>",
  "topic": "<topic>",
  "domain": "code" | "protocol",
  "complexity": "small" | "medium" | "deep",
  "questions": [
    {
      "id": "q1",
      "type": "qcm",
      "title": "Conceptual Check",
      "question": "Clear multiple choice question...",
      "options": [
        "A) First option",
        "B) Second option",
        "C) Third option",
        "D) Fourth option"
      ],
      "correct_option": "B",
      "explanation": "Why B is correct"
    }
  ]
}
"""

FACT_CHALLENGE_PROMPT = """You are an examiner testing atomic knowledge facts, definitions, and commands.
Generate EXACTLY 1 Multiple Choice Question (QCM) to test whether the user knows the given flash fact.

RULES:
1. ONLY return EXACTLY 1 question of type 'qcm'.
2. DO NOT return bug hunts, code snippets, or edge case scenarios.
3. Provide 4 options (A, B, C, D) with exactly one unambiguous correct answer matching the fact.

FORMAT REQUIREMENT:
Return valid JSON with:
{
  "card_id": "<card_id>",
  "topic": "<topic>",
  "domain": "fact",
  "complexity": "small",
  "questions": [
    {
      "id": "q1",
      "type": "qcm",
      "title": "Quick Fact Quiz",
      "question": "Clear multiple choice question testing the fact...",
      "options": [
        "A) First option",
        "B) Second option",
        "C) Third option",
        "D) Fourth option"
      ],
      "correct_option": "A",
      "explanation": "Why this option is correct based on the fact"
    }
  ]
}
"""

def challenge(card_id, is_daily=False):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    if card.get("type") == "context":
        emit({"success": False, "error": "Context anchors are workspace references and cannot be tested."})
        return

    is_fact = (card.get("type") == "fact")
    prompt_to_use = FACT_CHALLENGE_PROMPT if is_fact else CHALLENGE_PROMPT

    if is_fact:
        payload = {
            "card_id": card.get("id"),
            "topic": card.get("title") or card.get("topic"),
            "domain": card.get("domain", "fact"),
            "front": card.get("front", ""),
            "back": card.get("back", ""),
            "last_fail_feedback": card.get("last_fail_feedback", "")
        }
        domain = "fact"
        complexity = "small"
    else:
        primer = card.get("primer") or {}
        domain = primer.get("domain") or ("code" if extract_code_tokens(card.get("topic", "") + " " + " ".join(card.get("lines", []))) else "protocol")
        complexity = primer.get("complexity") or ("small" if len(card.get("lines", [])) <= 1 else "medium")

        payload = {
            "card_id": card.get("id"),
            "topic": card.get("title") or card.get("topic"),
            "category": card.get("category"),
            "domain": domain,
            "complexity": complexity,
            "lines": card.get("invariants") or card.get("lines", []),
            "archived_lines": card.get("archived_lines", []),
            "last_fail_feedback": card.get("last_fail_feedback", ""),
            "personal_traps": card.get("user_traps") or card.get("personal_traps", []),
            "primer": primer
        }

    try:
        raw_resp = call_llm(prompt_to_use, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        resp_data["card_id"] = card_id
        resp_data["success"] = True
        if is_daily:
            resp_data["is_daily_gauntlet"] = True

        questions = resp_data.get("questions", [])
        if not questions:
            raise ValueError("No questions returned by examiner.")

        # Store the active trial criteria in the card for subsequent grading
        card["active_trial"] = {
            "timestamp": int(time.time()),
            "domain": resp_data.get("domain", domain),
            "complexity": resp_data.get("complexity", complexity),
            "questions": questions
        }
        atomic_save_memory(cards)

        emit(resp_data)
    except Exception as e:
        emit({"success": False, "error": f"Challenge generation failed: {e}"})

# ---------------------------------------------------------
# CLI Command: grade <card_id> "<answer>"
# Multi-question grading with voice tolerance & line compression
# ---------------------------------------------------------
MULTI_GRADE_PROMPT = """You are a rigorous, fair technical code & conceptual examiner.
Grade the user's answers across all questions presented in the trial gauntlet.

VOICE-TO-TEXT TRANSCRIPTION TOLERANCE:
The user may have spoken their answers using Whisper dictation (Super+Alt+V).
Forgive minor phonetic transcription artifacts (e.g. 'pipe wire' instead of 'pipewire', 'dash capital S' instead of '-S', 'equals equals' instead of '==').
Focus strictly on whether their causal understanding, logic, and technical insight are correct.

GRADING CRITERIA:
- Evaluate each question fairly against its criteria.
- In 'q_results', provide an entry for every question present in 'questions' (e.g. q1, q2, ...).
- Calculate an overall score from 0.0 to 1.0 (Mastery graduation requires score >= 0.85).
- ALWAYS provide the canonical, authoritative 'correct_solution' for every question so the user can study what the exact model answer or code fix was, especially if they were wrong!
- If passed with score >= 0.85, provide a crisp 1-sentence 'compressed_summary' capturing the master-level lesson.
- ADAPTIVE PERSONAL TRAP EXTRACTION:
  If the user made any errors, had blindspots, or scored < 0.85, formulate EXACTLY ONE crisp, actionable 'personal_trap' sentence diagnosing the exact mistake or misconception they made (e.g. 'Assumed Promise callbacks run before the current synchronous block', or 'Confused sleep latency with caffeine absorption timing'). If user answered flawlessly, set 'personal_trap' to "".

OUTPUT JSON:
{
  "verdict": "pass" | "fail",
  "score": 0.0 to 1.0,
  "q_results": {
    "q1": {
      "verdict": "pass" | "fail",
      "comment": "Specific feedback on user's answer",
      "correct_solution": "The exact correct answer or option (e.g., 'Option B: ... because ...')"
    }
  },
  "strengths": "Summary of what they understood well",
  "blindspots": "Summary of what was missing, imprecise, or misunderstood",
  "personal_trap": "Concise 1-sentence personal trap or caveat that tripped them up, or empty string if perfect",
  "explanation": "Master-level clarification of the core concepts",
  "compressed_summary": "1-sentence distillation of the rule (only if pass)"
}
"""

def grade(card_id, user_answer_raw):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    active_trial = card.get("active_trial") or {}
    questions = active_trial.get("questions") or []

    # Parse user answers (may be JSON string of {"q1": "...", "q2": "..."} or raw text)
    user_answers = {}
    try:
        parsed = json.loads(user_answer_raw)
        if isinstance(parsed, dict):
            user_answers = parsed
        else:
            user_answers = {"q1": str(user_answer_raw)}
    except Exception:
        user_answers = {"q1": str(user_answer_raw)}

    payload = {
        "topic": card.get("topic"),
        "core_rules": card.get("lines"),
        "questions": questions,
        "user_answers": user_answers
    }

    try:
        raw_resp = call_llm(MULTI_GRADE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)

        verdict = resp_data.get("verdict", "fail").lower()
        score = float(resp_data.get("score", 0.0))
        now_iso = datetime.now(timezone.utc).isoformat()

        trial_record = {
            "timestamp": int(time.time()),
            "questions_count": len(questions),
            "user_answers": user_answers,
            "verdict": verdict,
            "score": score,
            "q_results": resp_data.get("q_results", {}),
            "feedback": resp_data.get("blindspots") or resp_data.get("explanation", ""),
            "personal_trap": resp_data.get("personal_trap", "")
        }

        if "trials" not in card:
            card["trials"] = []
        card["trials"].append(trial_record)
        card["last_reviewed"] = now_iso
        card["updated"] = now_iso

        # Adaptive Weakness Tracking: Auto-append personal trap if score < 0.85 or verdict != pass
        trap = (resp_data.get("personal_trap") or "").strip()
        if trap and trap.lower() not in ["none", "n/a", "no trap", "empty", "\"\"", "''"]:
            if "personal_traps" not in card or not isinstance(card["personal_traps"], list):
                card["personal_traps"] = []
            if not any(trap.lower() == existing.lower() for existing in card["personal_traps"]):
                card["personal_traps"].insert(0, trap)
                card["personal_traps"] = card["personal_traps"][:5]

        # Enforce score >= 0.85 for true mastery graduation
        is_fact = (card.get("type") == "fact")
        if verdict == "pass" and score >= 0.85:
            card["status"] = "mastered"
            card["mastery_score"] = score
            card["last_fail_feedback"] = ""
            # Compress lines on mastery for knowledge cards
            if not is_fact:
                compressed = resp_data.get("compressed_summary", "").strip()
                if compressed:
                    card["archived_lines"] = list(card.get("lines") or [])
                    card["lines"] = [f"Mastered Rule: {compressed}"]
                    card["invariants"] = card["lines"]
        else:
            card["status"] = "learning"
            card["mastery_score"] = score
            if verdict == "pass" and score < 0.85:
                card["last_fail_feedback"] = f"Passing score was {int(score*100)}%, but mastery graduation requires >= 85%. Review the edge cases and re-test to graduate."
            else:
                card["last_fail_feedback"] = resp_data.get("blindspots") or resp_data.get("explanation", "")

        # SM-2 Spaced Repetition Scheduling
        streak = 0
        for tr in reversed(card.get("trials", [])):
            if tr.get("verdict") == "pass" or float(tr.get("score") or 0) >= 0.7:
                streak += 1
            else:
                break

        if streak == 0:
            interval_days = 1
        elif streak == 1:
            interval_days = 3
        elif streak == 2:
            interval_days = 7
        elif streak == 3:
            interval_days = 14
        else:
            interval_days = min(60, int(14 * (2.0 ** (streak - 3))))

        next_review_date = datetime.now(timezone.utc) + timedelta(days=interval_days)
        card["next_review"] = next_review_date.isoformat()
        card["srs_data"] = {
            "score": round(score, 2),
            "streak": streak,
            "interval_days": interval_days,
            "next_review": next_review_date.isoformat(),
            "last_reviewed": now_iso
        }
        card["srs"] = card["srs_data"]
        card["user_traps"] = card.get("personal_traps", [])
        card["invariants"] = card.get("lines", [])

        # Clear the active trial
        card.pop("active_trial", None)
        atomic_save_memory(cards)
        hook_gauntlet_result(card, resp_data, cards)

        resp_data["card_id"] = card_id
        resp_data["status"] = card["status"]
        resp_data["success"] = True
        emit(resp_data)
    except Exception as e:
        emit({"success": False, "error": f"Grading failed: {e}"})

# ---------------------------------------------------------
# CLI Command: enrich <card_id>
# Adaptive high-density Technical / Conceptual Primer
# ---------------------------------------------------------
ENRICH_PROMPT = """You are an expert technical educator and knowledge architect.
Enrich this knowledge card into an authoritative, high-density primer tailored to its domain.

DOMAIN & SCOPE ADAPTATION:
1. Determine the domain:
   - "code": software development, programming languages, CLI commands, scripts, APIs, system configs.
   - "protocol": conceptual, methodologies, productivity, health/biology, translation, general reasoning.
2. Determine complexity:
   - "small": a single flag, simple lookup, or short isolated concept.
   - "medium": a standard concept with multiple rules or edge cases.
   - "deep": an intricate, multifaceted architectural or conceptual system.
3. AUDIT EXISTING NOTES FIRST:
   - If the card already has accurate, comprehensive lines from previous interactions, PRESERVE and distill their core substance. DO NOT replace them with generic hallucinated filler!
   - Remove only noise, irrelevant chit-chat, or duplicated trivialities.
4. CONTENT STRUCTURE:
   - 'mental_model': 2-3 dense sentences explaining the underlying cause-and-effect mechanics/principles and WHY it works this way.
   - 'rules': 2-4 actionable, definitive golden rules or invariants.
   - 'pitfall': 1 critical real-world edge case, race condition, or common failure mode.
   - 'snippet':
     - If domain is "code": 3-8 lines of clean, copy-pasteable canonical code, shell pipeline, or config.
     - If domain is "protocol": leave EMPTY string (""). DO NOT invent fake code or dummy bash commands!
   - 'protocol_flow':
     - If domain is "protocol": 2-4 concise, sequential steps or practical execution protocol.
     - If domain is "code": empty list ([]).

OUTPUT JSON:
{
  "domain": "code" | "protocol",
  "complexity": "small" | "medium" | "deep",
  "mental_model": "...",
  "rules": ["Rule 1", "Rule 2"],
  "pitfall": "...",
  "snippet": "...",
  "protocol_flow": ["Step 1", "Step 2"]
}
"""

def enrich(card_id):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return

    # Gather user context from lines and history sources
    sources_text = []
    if os.path.exists(HISTORY_PATH):
        try:
            with open(HISTORY_PATH, "r", encoding="utf-8") as f:
                hist = json.load(f)
                if isinstance(hist, list):
                    source_ids = set(str(s) for s in card.get("sources", []))
                    for item in hist:
                        if str(item.get("id")) in source_ids:
                            prompt = item.get("prompt") or ""
                            text = item.get("text") or ""
                            ans = item.get("answer") or ""
                            sources_text.append(f"User Query: {prompt} {text[:200]} -> Answer: {ans[:250]}")
        except Exception:
            pass

    payload = {
        "card_id": card.get("id"),
        "topic": card.get("topic"),
        "category": card.get("category", "general"),
        "current_notes": card.get("lines"),
        "archived_lines": card.get("archived_lines", []),
        "user_sources": sources_text[:3]
    }

    try:
        raw_resp = call_llm(ENRICH_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)

        now_iso = datetime.now(timezone.utc).isoformat()
        domain = resp_data.get("domain", "code" if extract_code_tokens(card.get("topic", "") + " " + " ".join(card.get("lines", []))) else "protocol")
        complexity = resp_data.get("complexity", "small" if len(card.get("lines", [])) <= 1 else "medium")

        card["primer"] = {
            "domain": domain,
            "complexity": complexity,
            "mental_model": resp_data.get("mental_model", ""),
            "rules": resp_data.get("rules", []),
            "pitfall": resp_data.get("pitfall", ""),
            "snippet": resp_data.get("snippet", "") if domain == "code" else "",
            "protocol_flow": resp_data.get("protocol_flow", []) if domain != "code" else [],
            "updated_at": now_iso
        }
        card["updated"] = now_iso
        atomic_save_memory(cards)

        emit({
            "success": True,
            "card_id": card_id,
            "topic": card.get("topic"),
            "primer": card["primer"]
        })
    except Exception as e:
        emit({"success": False, "error": f"Enrichment failed: {e}"})

# ---------------------------------------------------------
# CLI Command: consolidate <domain>
# Synthesizes fragmented micro-cards into an authoritative Domain Code Hub
# ---------------------------------------------------------
CONSOLIDATE_PROMPT = """You are a Principal Software Engineer and Technical Knowledge Architect.
Your task is to consolidate multiple fragmented cards from the same technical domain into ONE authoritative, cohesive Master Domain Code Hub.

CONSOLIDATION PRINCIPLES:
1. TECHNICAL DEPTH: Do NOT compress into 2 superficial bullet points. Preserve and synthesize all technical nuance, exact idioms, edge cases, and code patterns from the original cards.
2. MODULAR SECTIONS: Organize the knowledge into 2-4 logical, well-structured sections.
3. CONCISE CODE SNIPPETS: Each section must provide a short, focused, practical code snippet (under 8-10 lines max). Do NOT provide full boilerplate classes, endless imports, or package headers. Show only the clean, essential pattern.
4. PITFALLS & BLINDSPOTS: Retain and clearly list deadly traps, gotchas, and concurrency/memory pitfalls.
5. CLEAN DISTINCT TOPIC (5-7 WORDS MAX): Keep core languages and large frameworks separate. Ensure card topics are general, clean, and strictly 5 to 7 words maximum (e.g. 'Java Core & Concurrency Hub', 'Spring Boot Engineering Hub'). Never use long hyper-specific sentences for card titles.
6. EXTRACT ESSENTIAL GENERAL RULES (NOT SITUATIONAL EXAMPLES): Synthesize universal engineering principles, invariants, and syntax gotchas. Eliminate all situational project names, temporary filenames, and conversational history narratives.

OUTPUT FORMAT:
Return a JSON object with a single key 'card':
{
  "card": {
    "id": "card_<domain>_engineering_hub",
    "topic": "Domain & Framework Engineering Hub",
    "category": "<domain>",
    "type": "code_hub",
    "summary": "1-2 sentence high-level overview of the engineering domain.",
    "lines": [
      "Top synthesized high-yield rule 1 across the domain",
      "Top synthesized high-yield rule 2 across the domain"
    ],
    "sections": [
      {
        "id": "section_slug",
        "title": "Section Title",
        "rules": [
          "Actionable technical rule 1",
          "Actionable technical rule 2"
        ],
        "snippet": "```lang\\n// Production code snippet\\n...\\n```",
        "pitfalls": [
          "Deadly trap or common misstep"
        ]
      }
    ],
    "tags": ["domain", "tag1", "tag2"],
    "personal_traps": [
      "Personal traps gathered from user feedback"
    ]
  }
}
"""

def consolidate_domain(domain_query="java"):
    cards = load_memory(auto_demote=False)
    if not cards:
        emit({"success": False, "error": "No memory cards found."})
        return

    domain = (domain_query or "java").lower().strip()

    # Identify candidate cards matching this domain
    matched = []
    for c in cards:
        tags = [str(t).lower() for t in c.get("tags", [])]
        topic = (c.get("topic") or "").lower()
        cid = (c.get("id") or "").lower()
        if domain in tags or domain in topic or domain in cid:
            matched.append(c)

    if len(matched) < 2:
        emit({"success": False, "error": f"Found only {len(matched)} card(s) matching '{domain}'. At least 2 cards are needed to consolidate."})
        return

    payload = {
        "domain": domain,
        "cards_to_consolidate": [
            {
                "id": c.get("id"),
                "topic": c.get("topic"),
                "lines": c.get("lines", []),
                "tags": c.get("tags", []),
                "primer": c.get("primer"),
                "personal_traps": c.get("personal_traps", []),
                "last_fail_feedback": c.get("last_fail_feedback", "")
            }
            for c in matched
        ]
    }

    try:
        raw_resp = call_llm(CONSOLIDATE_PROMPT, json.dumps(payload, ensure_ascii=False), expect_json=True)
        resp_data = parse_json_safely(raw_resp)
        new_card_data = resp_data.get("card")
        if not new_card_data or not isinstance(new_card_data, dict):
            emit({"success": False, "error": "LLM failed to return a valid consolidated card structure."})
            return
    except Exception as e:
        emit({"success": False, "error": f"Consolidation LLM call failed: {e}"})
        return

    now_iso = datetime.now(timezone.utc).isoformat()
    matched_ids = {str(c.get("id")) for c in matched}

    all_sources = set()
    all_trials = []
    all_traps = list(new_card_data.get("personal_traps", []))
    all_relations = []
    max_score = 0.0
    any_mastered = False

    for c in matched:
        for s in c.get("sources", []):
            if s:
                all_sources.add(str(s))
        for t in c.get("trials", []):
            all_trials.append(t)
        for trap in c.get("personal_traps", []):
            if trap and trap not in all_traps:
                all_traps.append(trap)
        if c.get("last_fail_feedback") and c["last_fail_feedback"] not in all_traps:
            all_traps.append(c["last_fail_feedback"])
        for rel in c.get("relations", []):
            if str(rel.get("target_id")) not in matched_ids:
                all_relations.append(rel)
        if c.get("status") == "mastered":
            any_mastered = True
        try:
            score = float(c.get("mastery_score", 0.0))
            if score > max_score:
                max_score = score
        except Exception:
            pass

    all_trials.sort(key=lambda t: t.get("timestamp", 0))

    consolidated_id = new_card_data.get("id") or f"card_{domain}_engineering_hub"
    consolidated_card = {
        "id": consolidated_id,
        "topic": new_card_data.get("topic") or f"{domain.capitalize()} Engineering Hub",
        "category": domain,
        "type": "code_hub",
        "status": "mastered" if any_mastered else "learning",
        "mastery_score": max_score,
        "summary": new_card_data.get("summary", ""),
        "lines": new_card_data.get("lines", []),
        "sections": new_card_data.get("sections", []),
        "tags": list(set(new_card_data.get("tags", [domain]) + [domain])),
        "sources": list(all_sources),
        "trials": all_trials,
        "personal_traps": all_traps,
        "relations": all_relations,
        "created": now_iso,
        "updated": now_iso,
        "last_reviewed": now_iso,
        "_ts": int(time.time() * 1000)
    }

    # Replace matched cards with the new consolidated card
    remaining_cards = [c for c in cards if str(c.get("id")) not in matched_ids]
    remaining_cards.insert(0, consolidated_card)
    atomic_save_memory(remaining_cards)

    emit({
        "success": True,
        "consolidated_id": consolidated_id,
        "topic": consolidated_card["topic"],
        "sections_count": len(consolidated_card.get("sections", [])),
        "merged_card_count": len(matched),
        "deleted_ids": list(matched_ids),
        "total_cards": len(remaining_cards)
    })


# ---------------------------------------------------------
# CLI Command: daily_challenge
# Spaced repetition gauntlet prioritizing due & blindspot cards
# ---------------------------------------------------------
def daily_challenge():
    cards = load_memory()
    testable_cards = [c for c in cards if c.get("type") != "context"]
    if not testable_cards:
        emit({"success": False, "error": "No testable memory cards found to generate daily gauntlet."})
        return

    now_epoch = time.time()

    def card_priority(c):
        # Priority 1: Unresolved blindspots / personal traps
        if c.get("status") != "mastered" and c.get("last_fail_feedback"):
            return 10
        # Priority 2: Due for review based on SM-2 next_review
        nr_str = (c.get("srs_data") and c["srs_data"].get("next_review")) or c.get("next_review")
        if nr_str:
            try:
                nr_dt = datetime.fromisoformat(nr_str.replace("Z", "+00:00"))
                overdue_seconds = now_epoch - nr_dt.timestamp()
                if overdue_seconds > 0:
                    return 15 - min(5, int(overdue_seconds / 86400))
            except Exception:
                pass
        # Priority 3: Unmastered concepts
        if c.get("status") != "mastered":
            return 25
        # Priority 4: Mastered cards
        return 50

    sorted_candidates = sorted(testable_cards, key=card_priority)
    chosen_card = sorted_candidates[0]
    challenge(chosen_card.get("id"), is_daily=True)

def remove_trap(card_id, trap_text):
    cards = load_memory()
    card = next((c for c in cards if c.get("id") == card_id), None)
    if not card:
        emit({"success": False, "error": f"Card '{card_id}' not found."})
        return
    traps = card.get("personal_traps", [])
    card["personal_traps"] = [t for t in traps if t.strip() != trap_text.strip()]
    atomic_save_memory(cards)
    emit({"success": True, "personal_traps": card["personal_traps"]})

def quick_card(source_text, answer_text, action_type="explain"):
    """Rapidly extracts a high-yield memory flashcard from a Q&A interaction.
    Outputs a typed card (knowledge or fact) matching the current schema.
    """
    # Decide card type: translate/simple vocab → fact; code/explain/deep → knowledge
    is_fact_action = action_type in ("translate", "examples")
    is_fact_content = (
        len((source_text or "").strip()) < 120
        and len(extract_code_tokens(source_text or "")) == 0
        and action_type not in ("explain", "ask")
    )
    emit_as_fact = is_fact_action or is_fact_content

    if emit_as_fact:
        system_instruction = (
            "You are a knowledge classifier. From this Q&A, extract a single atomic flash fact.\n"
            "Return a JSON object with:\n"
            "- type: always \"fact\"\n"
            "- domain: one word (e.g. vocab, linux, general, networking)\n"
            "- front: 1-sentence question or prompt\n"
            "- back: 1-sentence authoritative answer\n"
            "- tags: array of 2-3 lowercase tags\n"
            "DO NOT return generic summaries. Output STRICT JSON."
        )
    else:
        system_instruction = (
            "You are a knowledge classifier. From this Q&A, extract a deep engineering concept card.\n"
            "Return a JSON object with:\n"
            "- type: always \"knowledge\"\n"
            "- domain: one word (e.g. code, architecture, networking, devops)\n"
            "- title: short crisp title (3-7 words)\n"
            "- mental_model: 1-2 sentence core mental model\n"
            "- invariants: array of 2-4 concise actionable rules\n"
            "- snippet: optional code string, empty string if not applicable\n"
            "- user_traps: array of 1-2 common mistakes the user might make\n"
            "- tags: array of 3-5 lowercase tags\n"
            "DO NOT return generic summaries. Output STRICT JSON."
        )

    user_payload = f"SOURCE / CONTEXT:\n{source_text[:2000]}\n\nASSISTANT ANSWER:\n{answer_text[:4000]}"
    try:
        raw_res = call_llm(system_instruction, user_payload, expect_json=True, temperature=0.2)
        data = parse_json_safely(raw_res)
        if not data or not isinstance(data, dict):
            emit({"success": False, "error": "Failed to parse AI response into card schema"})
            return

        now_iso = datetime.now(timezone.utc).isoformat()
        next_rev = (datetime.now(timezone.utc) + timedelta(days=1)).isoformat()
        ctype = data.get("type", "fact" if emit_as_fact else "knowledge")

        if ctype == "fact":
            front = (data.get("front") or source_text[:80]).strip()
            back = (data.get("back") or answer_text[:200]).strip()
            card_id = "fact_" + re.sub(r"[^a-z0-9_]+", "_", front.lower())[:40].strip("_")
            new_card = {
                "id": card_id,
                "type": "fact",
                "domain": data.get("domain", "general"),
                "title": front,
                "topic": front,
                "front": front,
                "back": back,
                "lines": [back],
                "tags": data.get("tags", []),
                "status": "learning",
                "mastery_score": 0.0,
                "srs_data": {"score": 0.0, "streak": 0, "interval_days": 1, "next_review": next_rev, "last_reviewed": now_iso},
                "next_review": next_rev,
                "created": now_iso,
                "updated": now_iso,
                "_ts": int(time.time() * 1000)
            }
        else:
            title = (data.get("title") or data.get("topic") or "Knowledge Concept").strip()
            card_id = "card_" + re.sub(r"[^a-z0-9_]+", "_", title.lower())[:40].strip("_")
            new_card = {
                "id": card_id,
                "type": "knowledge",
                "domain": data.get("domain", "code"),
                "title": title,
                "topic": title,
                "mental_model": data.get("mental_model", ""),
                "summary": data.get("mental_model", ""),
                "invariants": data.get("invariants", []),
                "lines": data.get("invariants", []),
                "snippet": data.get("snippet", ""),
                "user_traps": data.get("user_traps", []),
                "personal_traps": data.get("user_traps", []),
                "tags": data.get("tags", []),
                "status": "learning",
                "mastery_score": 0.0,
                "primer": {},
                "srs_data": {"score": 0.0, "streak": 0, "interval_days": 1, "next_review": next_rev, "last_reviewed": now_iso},
                "srs": {"score": 0.0, "streak": 0, "interval_days": 1, "next_review": next_rev},
                "next_review": next_rev,
                "created": now_iso,
                "updated": now_iso,
                "_ts": int(time.time() * 1000)
            }

        cards = load_memory(auto_demote=False)
        target_title = new_card.get("title") or new_card.get("front") or new_card.get("topic") or ""
        norm_target = normalize_concept_key(target_title)
        existing_idx = -1
        for i, c in enumerate(cards):
            if c.get("id") == card_id:
                existing_idx = i
                break
            c_title = c.get("title") or c.get("topic") or c.get("front") or ""
            c_norm = normalize_concept_key(c_title)
            if norm_target and c_norm:
                if norm_target == c_norm:
                    existing_idx = i
                    break
                if len(norm_target) >= 10 and len(c_norm) >= 10 and (norm_target in c_norm or c_norm in norm_target):
                    existing_idx = i
                    break
        if existing_idx >= 0:
            existing = cards[existing_idx]
            if ctype == "fact":
                existing.update({"back": new_card["back"], "front": new_card["front"],
                                 "title": new_card["title"], "updated": now_iso})
            else:
                merged_invariants = list(dict.fromkeys(
                    (existing.get("invariants") or existing.get("lines") or []) + new_card["invariants"]
                ))
                existing.update({
                    "mental_model": new_card["mental_model"],
                    "summary": new_card["mental_model"],
                    "invariants": merged_invariants,
                    "lines": merged_invariants,
                    "updated": now_iso
                })
            saved_card = existing
        else:
            cards.insert(0, new_card)
            saved_card = new_card

        atomic_save_memory(cards)
        emit({"success": True, "card": saved_card, "message": f"Saved {ctype} card: '{saved_card.get('title', saved_card.get('front', ''))}'"})
    except Exception as e:
        emit({"success": False, "error": str(e)})

# ---------------------------------------------------------
# Main CLI Dispatcher
# ---------------------------------------------------------
def main():
    if len(sys.argv) < 2:
        emit({
            "error": "USAGE",
            "message": "Usage: memory_engine.py <distill|get_context|challenge|grade|enrich|daily_challenge|consolidate|remove_trap|quick_card|learner_profile> [args...]"
        })
        sys.exit(1)

    cmd = sys.argv[1].lower()

    if cmd == "inspect_memory":
        inspect_memory_file()
    elif cmd == "distill":
        distill()
    elif cmd == "quick_card":
        src = sys.argv[2] if len(sys.argv) > 2 else ""
        ans = sys.argv[3] if len(sys.argv) > 3 else ""
        act = sys.argv[4] if len(sys.argv) > 4 else "explain"
        quick_card(src, ans, act)
    elif cmd == "get_context":
        query = sys.argv[2] if len(sys.argv) > 2 else ""
        get_context(query)
    elif cmd == "challenge":
        if len(sys.argv) < 3:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py challenge <card_id>"})
            sys.exit(1)
        challenge(sys.argv[2])
    elif cmd == "daily_challenge":
        daily_challenge()
    elif cmd == "grade":
        if len(sys.argv) < 4:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py grade <card_id> \"<answer>\""})
            sys.exit(1)
        grade(sys.argv[2], sys.argv[3])
    elif cmd == "enrich":
        if len(sys.argv) < 3:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py enrich <card_id>"})
            sys.exit(1)
        enrich(sys.argv[2])
    elif cmd == "consolidate":
        domain = sys.argv[2] if len(sys.argv) > 2 else "java"
        consolidate_domain(domain)
    elif cmd == "remove_trap":
        if len(sys.argv) < 4:
            emit({"error": "MISSING_ARG", "message": "Usage: memory_engine.py remove_trap <card_id> \"<trap_text>\""})
            sys.exit(1)
        remove_trap(sys.argv[2], sys.argv[3])
    elif cmd == "learner_profile":
        emit(sync_learner_profile())
    else:
        emit({"error": "UNKNOWN_COMMAND", "command": cmd})
        sys.exit(1)

if __name__ == "__main__":
    main()
