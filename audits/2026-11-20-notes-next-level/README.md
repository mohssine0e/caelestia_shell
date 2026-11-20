# Notes: understand deeply, recall quickly

**Date:** 2026-11-20 · **Reviewed revision:** `10b442d3`  
**Status:** audit and proposed design only; application implementation has not started.

**Start here: [Complete master plan and live checklist](MASTER_PLAN.md).** This is the authoritative implementation scope, phase order, acceptance criteria, and continuation record. The files below provide supporting evidence and design detail.

## The recommendation

Build a personal engineering handbook around **concepts with adjustable depth**. Keep your fast capture box. Give each concept one dependable page with two views: **Understand** and **Recall**. Both read the same saved material. Switching views must never summarize away or delete the original detail.

Your confirmed preference is **“Understand deeply now, look up quickly later.”** You work in Java backend engineering and are interested in Linux, DevOps, and cloud. You want rules, definitions, working syntax, exceptions, and explanations of why things exist. You also want to stop rereading explanations once you understand them.

The current system works well as a compact collection of bullets and commands. Its content model is the main constraint: it assigns one subsection to an entire capture and compresses that capture into a few bullets. More visual polish alone will not solve this.

## What the audit found in your actual notes

- There are **80 undeleted records**: Git 45, Docker 17, RabbitMQ 10, Java 1, Kubernetes 1, and 6 records with General/empty topics. These are storage counts, not a measure of knowledge or proficiency.
- Your Java capture is **9,536 characters**, covering seven broad areas: memory/references, equality/hashing, collections, concurrency, CAS, executors, and virtual threads. Its structured representation has **six bullets and two snippets**, grouped as “Modern Language Features.” The raw source survives, but the normal review presentation loses its organization and much of its detail.
- Docker image-layer material is classified under Compose. A local reproduction shows the generic word **“stack”** can trigger that classification.
- Several Docker and RabbitMQ entries overlap. The system hides some exact duplicates while leaving conceptual repetition.
- Only four undeleted records have related IDs. Linking exists, but it does not yet explain *why* a connection matters.

## Read this plan in order

| File | What it decides |
|---|---|
| [01 — Audit](01-current-audit.md) | Confirmed bugs, content loss in the displayed view, and limits of the current implementation. |
| [02 — Learning model](02-learning-model.md) | How depth, explanations, examples, personal understanding, and connections should work. |
| [03 — Window design](03-window-design.md) | A concrete single-window layout, navigation, search, and controls. |
| [04 — Implementation plan](04-implementation-plan.md) | Data model, migration, AI pipeline, implementation order, and acceptance gates. |

## The first useful release

Repair capture/merge reliability, then use your existing Java capture to build the first concept pages. Demonstrate **pass-by-value**, **equality/hashCode**, and **concurrency choices** with full source retention and Understand/Recall views. Add search that lands on the exact explanation or example. Only then upgrade gap generation.

This provides a concrete test: can you learn the reasoning once, then find the relevant rule and example in a few seconds a week later?

## Keep, simplify, defer

**Keep:** silent Super+/ capture, one window, topic grouping, command copying, global theme tokens, raw captures, reviewable suggestions, and independent Notes storage.

**Simplify:** move Delete, reanalysis, full export, and source maintenance into a menu; move topic generation out of the permanent header; replace a flat wall of bullets with concept headings and expandable explanation blocks.

**Defer:** graph visualization, dashboards, learning scores, automatic quizzes, spaced repetition, execution of snippets, and integration into Memory/Gauntlet. They are not necessary for the first successful version.

## Review evidence and limits

Inspected QML, service queues, Python storage/AI logic, technical note samples using a read-only SQLite connection, and the live 900×620 review window. Ran all **43 existing backend tests**, which pass. Additional isolated reproductions confirmed invalid merge targeting, stale structured merge content, the smart-upsert sensitive-input bypass, and the Docker “stack” misclassification. No real note was used in an AI request during this audit.

The application was opened briefly for visual inspection. No implementation, user-note edits, migration, shell reload, or commit was intentionally performed. The existing `connect()` can perform normalization even on a list operation; this behavior is itself listed in the audit. Small-window and large-library concerns are code-review findings, not measured performance results.
