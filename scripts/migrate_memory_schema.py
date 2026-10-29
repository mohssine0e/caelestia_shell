#!/usr/bin/env python3
"""
Migration script for Caelestia Knowledge & Mastery cards.
Standardizes schema, deduplicates hub sections, calculates SM-2 SRS intervals,
populates missing personal traps, and builds bidirectional knowledge graph edges.
"""

import json
import os
import sys
from datetime import datetime, timezone, timedelta

MEMORY_PATH = os.path.expanduser("~/.config/caelestia/assistant_memory.json")

CATEGORY_MAP = {
    "card_java_21_virtual_threads": "java",
    "card_java_core_hub": "java",
    "card_spring_boot_hub": "spring",
    "m_translation_vocab": "general",
    "m_software_mvp": "architecture",
    "m_architecture_paas": "architecture",
    "m_ai_llm_tldr": "ai",
    "m_git_contributions": "devops",
    "m_translation_formatting_rtl": "ui",
    "m_linux_yay_pacman": "linux",
    "m_programming_math": "general",
    "m_memory_ui_design": "architecture",
    "m_architecture_adr_containers": "architecture",
    "m_docker_concepts_interview": "devops",
    "m_networking_osi_tcpip": "networking",
    "m_terraform_iac": "devops",
    "card_networking_uri_url_urn": "networking"
}

TIER_MAP = {
    "card_java_core_hub": "hub",
    "card_spring_boot_hub": "hub",
    "m_translation_vocab": "primitive",
    "m_programming_math": "primitive",
    "m_linux_yay_pacman": "primitive"
}

DOMAIN_MAP = {
    "card_java_21_virtual_threads": "code",
    "card_java_core_hub": "code",
    "card_spring_boot_hub": "code",
    "m_architecture_adr_containers": "code",
    "m_docker_concepts_interview": "code",
    "m_terraform_iac": "code",
    "m_programming_math": "code",
    "m_git_contributions": "code",
    "m_translation_formatting_rtl": "code",
    "m_memory_ui_design": "code",
    "m_linux_yay_pacman": "protocol",
    "m_software_mvp": "protocol",
    "m_architecture_paas": "protocol",
    "m_networking_osi_tcpip": "protocol",
    "card_networking_uri_url_urn": "protocol",
    "m_translation_vocab": "protocol",
    "m_ai_llm_tldr": "protocol"
}

TRAP_ENRICHMENTS = {
    "m_software_mvp": [
        "Conflating MVP with an unviable low-quality prototype; cutting core data integrity instead of narrowing product scope."
    ],
    "m_architecture_paas": [
        "Deploying multi-node Kubernetes clusters on single-machine or low-RAM environments without accounting for 2GB+ control plane overhead."
    ],
    "m_ai_llm_tldr": [
        "Treating LLM token probability as deterministic logic or true programmatic state storage."
    ],
    "m_git_contributions": [
        "Expecting commits pushed to personal feature branches to register on the GitHub profile contribution graph without merging to the default branch."
    ],
    "m_translation_formatting_rtl": [
        "Mixing hardcoded left/right CSS/QML alignments in bilingual apps instead of using directional logical anchors."
    ],
    "m_linux_yay_pacman": [
        "Running yay with sudo (which breaks unprivileged PKGBUILD building) instead of standard user yay execution."
    ],
    "m_programming_math": [
        "Assuming floating-point division by zero raises an exception in all languages (e.g. IEEE 754 returns Infinity instead of throwing)."
    ],
    "m_memory_ui_design": [
        "Triggering unbounded background AI distillations on every clipboard change, leading to token exhaustion and rate limits."
    ],
    "m_architecture_adr_containers": [
        "Pulling heavy third-party Docker SDKs with 20+ transitive dependencies for simple lifecycle commands instead of ProcessBuilder CLI invocation."
    ],
    "m_docker_concepts_interview": [
        "Confusing container isolation (shared host kernel namespaces) with true hypervisor VM hardware virtualization."
    ],
    "m_networking_osi_tcpip": [
        "Treating the 7-layer OSI model as an actual network implementation protocol rather than a conceptual reference model."
    ],
    "m_terraform_iac": [
        "Manually editing cloud infrastructure in the provider console, causing out-of-band state file drift."
    ],
    "card_networking_uri_url_urn": [
        "Assuming all URIs are URLs that can be resolved over the network, ignoring location-independent URN identifiers."
    ],
    "m_translation_vocab": [
        "Translating technical acronyms literally rather than translating their established industry meaning."
    ]
}

def deduplicate_hub_sections(card_id, sections):
    """Cleanly merges redundant sections in hub cards."""
    if not sections:
        return []
    
    if card_id == "card_java_core_hub":
        return [
            {
                "id": "concurrent_collections",
                "title": "Concurrent Collections & Atomics",
                "rules": [
                    "ConcurrentHashMap uses bucket-level locking and CAS operations for lock-free reads.",
                    "CopyOnWriteArrayList clones the array on mutation under a lock, keeping reads completely non-blocking.",
                    "Use atomic `computeIfAbsent()` instead of composite check-then-act logic."
                ],
                "snippet": "var registry = new ConcurrentHashMap<String, Service>();\nregistry.computeIfAbsent(id, k -> loadService(k));"
            },
            {
                "id": "virtual_threads_process",
                "title": "Virtual Threads & Process Execution",
                "rules": [
                    "Virtual threads detach from OS threads during blocking I/O; never use them for CPU-bound loops.",
                    "Use ProcessBuilder for clean subprocess management without heavy external SDK dependencies.",
                    "Avoid synchronized blocks on virtual threads when possible to prevent carrier thread pinning."
                ],
                "snippet": "try (var executor = Executors.newVirtualThreadPerTaskExecutor()) {\n    executor.submit(() -> fetchRemotePayload());\n}"
            },
            {
                "id": "cas_concurrency_primitives",
                "title": "CAS & Mutex Primitives",
                "rules": [
                    "Use AtomicReference and VarHandle for non-blocking lock-free state transitions.",
                    "Prefer ReentrantLock over synchronized blocks when virtual thread compatibility is required.",
                    "Volatile guarantees visibility and ordering via memory barriers, but not compound atomicity."
                ],
                "snippet": "private final AtomicReference<State> state = new AtomicReference<>(State.IDLE);\nstate.compareAndSet(State.IDLE, State.RUNNING);"
            }
        ]

    if card_id == "card_spring_boot_hub":
        return [
            {
                "id": "jpa_dto_projections",
                "title": "JPA Lifecycle & DTO Records",
                "rules": [
                    "Decouple domain entities from JSON serialization using Java `record` DTO projections to prevent lazy-load exceptions.",
                    "Use read-only Spring Data projections for read-heavy query performance.",
                    "Never return managed entities directly from REST controller endpoints."
                ],
                "snippet": "public record UserDTO(Long id, String email) {}\n// Spring Data JPA projection:\nUserDTO findProjectedById(Long id);"
            },
            {
                "id": "sse_realtime_streaming",
                "title": "Server-Sent Events & Log Streaming",
                "rules": [
                    "Use SseEmitter for unidirectional real-time event streaming to web clients over HTTP.",
                    "Always configure emitter timeout and error callbacks (`onCompletion`, `onTimeout`, `onError`).",
                    "Debounce high-frequency server events to avoid overflowing browser client render buffers."
                ],
                "snippet": "SseEmitter emitter = new SseEmitter(60_000L);\nemitter.onCompletion(() -> log.info(\"Stream done\"));\nemitter.send(SseEmitter.event().name(\"log\").data(chunk));"
            },
            {
                "id": "async_execution_boundaries",
                "title": "Async Execution & Proxy Traps",
                "rules": [
                    "Methods annotated with `@Async` must be public and invoked from an external Spring bean to pass through the AOP proxy.",
                    "Self-invocation (`this.asyncMethod()`) bypasses the proxy and executes synchronously on the caller thread.",
                    "Configure a dedicated ThreadPoolTaskExecutor to avoid unbounded default task spawning."
                ],
                "snippet": "@Async(\"taskExecutor\")\npublic CompletableFuture<Report> generateReportAsync() {\n    return CompletableFuture.completedFuture(compute());\n}"
            }
        ]

    # For other cards, deduplicate by normalized title
    seen = {}
    result = []
    for s in sections:
        norm = s.get("title", "").strip().lower()
        if norm and norm not in seen:
            seen[norm] = True
            result.append(s)
    return result

def calculate_sm2(card):
    """Computes SM-2 SRS schedule based on past trial results."""
    trials = card.get("trials", [])
    now = datetime.now(timezone.utc)
    
    streak = 0
    latest_score = float(card.get("mastery_score") or 0.0)
    
    if trials:
        # Scan backward from most recent trial
        for tr in reversed(trials):
            verdict = tr.get("verdict", "")
            sc = float(tr.get("score") or 0.0)
            if verdict == "pass" or sc >= 0.7:
                streak += 1
            else:
                break
        last_trial = trials[-1]
        latest_score = float(last_trial.get("score") or latest_score)

    # SM-2 intervals
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

    # Last reviewed timestamp
    lr_raw = card.get("last_reviewed") or card.get("updated") or card.get("created")
    try:
        if lr_raw:
            lr_date = datetime.fromisoformat(lr_raw.replace("Z", "+00:00"))
        else:
            lr_date = now
    except Exception:
        lr_date = now

    next_review_date = lr_date + timedelta(days=interval_days)
    
    # Status calculation
    is_mastered = (latest_score >= 0.8 and streak >= 2)
    is_overdue = (now >= next_review_date)
    
    if is_mastered and not is_overdue:
        status = "mastered"
    elif is_overdue:
        status = "learning"  # Due for review
    else:
        status = "learning"

    return {
        "score": round(latest_score, 2),
        "streak": streak,
        "interval_days": interval_days,
        "next_review": next_review_date.isoformat(),
        "status": status
    }

def main():
    if not os.path.exists(MEMORY_PATH):
        print(f"Error: {MEMORY_PATH} not found.")
        sys.exit(1)

    with open(MEMORY_PATH, "r", encoding="utf-8") as f:
        cards = json.load(f)

    print(f"Loaded {len(cards)} cards for migration.")
    cards_by_id = {c["id"]: c for c in cards}

    # Pass 1: Normalization, Invariants, SRS, and Traps
    for c in cards:
        cid = c.get("id")
        
        # 1. Category & Tier & Domain
        c["category"] = c.get("category") or CATEGORY_MAP.get(cid, "general")
        c["tier"] = TIER_MAP.get(cid, "hub" if c.get("sections") else "concept")
        c["domain"] = DOMAIN_MAP.get(cid, "code" if any(t in ["java", "python", "git", "docker", "terraform"] for t in c.get("tags", [])) else "protocol")
        
        # 2. Invariants & Lines synchronization
        invariants = c.get("invariants") or c.get("lines") or []
        # Clean markdown bullets if present
        clean_inv = [line.strip().lstrip("-*•").strip() for line in invariants if line and line.strip()]
        c["invariants"] = clean_inv
        c["lines"] = clean_inv  # Backwards compatibility

        # 3. Traps Enrichment
        existing_traps = c.get("personal_traps") or c.get("traps") or []
        if not existing_traps and cid in TRAP_ENRICHMENTS:
            existing_traps = TRAP_ENRICHMENTS[cid]
        c["traps"] = existing_traps
        c["personal_traps"] = existing_traps  # Backwards compatibility

        # 4. Hub Sections Deduplication
        if c.get("sections"):
            c["sections"] = deduplicate_hub_sections(cid, c["sections"])

        # 5. SRS Scheduling
        srs = calculate_sm2(c)
        c["srs"] = srs
        c["mastery_score"] = srs["score"]
        c["status"] = srs["status"]
        c["next_review"] = srs["next_review"]

        # 6. Ensure clean summary
        if not c.get("summary") and clean_inv:
            c["summary"] = clean_inv[0]

    # Pass 2: Bidirectional Knowledge Graph
    for c in cards:
        rels = c.get("relations") or []
        c["relations"] = rels

    # Add reciprocal edges
    for c in cards:
        src_id = c["id"]
        src_topic = c["topic"]
        for r in (c.get("relations") or []):
            target_id = r.get("target_id")
            rtype = r.get("type", "related")
            if target_id and target_id in cards_by_id:
                target_card = cards_by_id[target_id]
                target_rels = target_card.setdefault("relations", [])
                
                # Determine reciprocal relation
                recip_type = "enables" if rtype == "prerequisite" else ("prerequisite" if rtype == "enables" else "related")
                
                # Check if reciprocal edge already exists
                exists = any(tr.get("target_id") == src_id for tr in target_rels)
                if not exists:
                    target_rels.append({
                        "target_id": src_id,
                        "target_topic": src_topic,
                        "type": recip_type,
                        "reason": f"Reciprocal relation from '{src_topic}'"
                    })

    # Save migrated cards
    temp_path = MEMORY_PATH + ".tmp"
    with open(temp_path, "w", encoding="utf-8") as f:
        json.dump(cards, f, indent=2, ensure_ascii=False)
    os.replace(temp_path, MEMORY_PATH)

    print("Migration completed successfully!")
    print(f"All {len(cards)} cards normalized to unified schema.")

if __name__ == "__main__":
    main()
