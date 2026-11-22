# Learning model and product goals

> This document defines the intended learning experience. It is not a claim that all listed controls are implemented. The active UI remains the established topic/subconcept view; concept detail opens from its Deeper detail section. See [current state](README.md).

## One concept, different amounts of detail

A topic is a broad home such as Java. An area is a navigational group such as Memory & References. A concept is a focused question, such as **“What does Java pass-by-value actually copy?”** A capture is the original material you pasted; it can support several concepts.

Keep these distinct. A single large Java capture should create several connected concept pages without requiring you to split it by hand or duplicate the source.

### Understand

For a new concept, show a short orientation followed by the explanation in a useful order:

1. **Problem:** what would be awkward or impossible without this concept?
2. **Meaning and name:** what the term describes; documented naming history only when supported.
3. **Mechanism:** what changes, where, and in what order; a small diagram when useful.
4. **Rules and boundaries:** what is guaranteed, what is conditional, and common misconceptions.
5. **Example:** a minimal piece of code/command/configuration with expected behavior.
6. **Choice:** when to use it, the closest alternative, and the relevant tradeoff.

These are optional content roles, not six mandatory empty boxes. A small command might need just its effect, arguments, and a useful example. A concurrency concept deserves more reasoning. Historical trivia must not crowd out practical understanding.

### Recall

Show a definition, three to five useful rules, the primary example or command, and any caveat essential to correct use. Keep source and version information available. Offer “Why?” on the rule that needs explanation.

Do not truncate meaning to hit a bullet count. A critical condition stays with its rule. Large explanations are collapsed but retained. Switching modes is a local view operation and makes no AI request.

New concepts initially open in Understand. “Use Recall next time” remembers your preference for this concept. Do not infer competence from how many times you opened a page. You can always reopen any explanation.

This use of progressive disclosure follows the general idea of showing core information first and revealing additional detail on demand; the specific two-view design is our proposal for your workflow. [NN/g: Progressive Disclosure](https://www.nngroup.com/articles/progressive-disclosure/)

## Make curiosity a useful action

Select a term or expand a rule and get a small contextual menu:

- **Why does this work?** Explain that rule's mechanism.
- **Why this name?** Explain terminology; distinguish a descriptive interpretation from documented origin.
- **Compared with…** Contrast a genuinely adjacent choice on the same decision criteria.
- **Show a counterexample.** Reveal where a tempting generalization fails.

The answer appears inline, under the relevant concept, with Keep/Dismiss when it adds new material. It must not open an unrelated assistant conversation or regenerate the entire topic. Reuse a saved answer when available.

**Depth stop rule:** explain until the current question and its essential prerequisites are understandable. Offer unresolved prerequisites as links. Do not recursively generate all of Java, the JVM, CPU architecture, and operating systems because you asked about one variable assignment.

## Example from your Java notes

**Concept:** Java pass-by-value  
**Area:** Memory & References

**Recall:** A method receives a copy of each argument value. A copied object reference can still identify the same object: mutating that object is visible through another reference, but reassigning the parameter does not reassign the caller's variable.

```java
static void change(User user) {
    user.name = "Youssef";
    user = new User("Sara");
}

User u = new User("Adam");
change(u);
System.out.println(u.name); // Youssef
```

Display this as a **fragment** whose prerequisite is a mutable `User` class, not as a standalone runnable program.

**Understand adds:** distinguish the variable, the reference value, and the object; step through the copied reference; show why field mutation and parameter reassignment differ. A tiny diagram is enough:

```text
caller u ──┐
           ├──> User object
parameter ─┘

Reassigning parameter changes only its arrow.
```

**Terminology:** here “value” includes reference values. This clarifies the name without inventing an origin story. Java's specification describes argument evaluation and the creation/initialization of method parameter variables. [JLS §15.12.4](https://docs.oracle.com/javase/specs/jls/se25/html/jls-15.html#jls-15.12.4)

**Useful connections:** object identity, mutation, immutability. A later “Compared with” can explain reference passing in another language if requested; it should not mix unrelated languages into the default Java page.

## Three high-value additions

### 1. Explanation attached to the rule

Keep the rule and its reason together. You can collapse the reason after learning it. This is more useful for your preferences than accumulating more unconnected bullets.

### 2. Worked examples with a counterexample

For each difficult concept, preserve one small example, its expected result, and one variation that changes the result. For commands, show placeholders, prerequisites, and whether they change state. Copy only the command/code, without the shell prompt or prose. Never execute it automatically.

### 3. Decisions you can reuse at work

A compact comparison can help choose between mechanisms already in your notes: `volatile`, locking, and atomic operations; or message routing options in RabbitMQ. Store the condition, choice, and reason together. Scope claims to versions and evidence. Do not turn context-dependent engineering decisions into universal “best practices.”

## Better gap filling

“Fill gaps” should ask what prevents you from understanding or using the selected concept:

| Existing material | Valuable missing material |
|---|---|
| Definition only | Mechanism plus a minimal example. |
| Code with no explanation | What changes, expected output, and prerequisites. |
| Rule with no boundary | Condition, exception, or counterexample. |
| Two similar alternatives | Decision criteria and a contrasting example. |
| A familiar concept already well covered | Return no additions. |

For a selected concept/area, stay within that scope. Area review is explicit; do not add an All scope that mixes unrelated sections. Present a small prioritized batch; clearly distinguish “missing section proposed” from “new fact in existing section.” Never imply a topic is complete merely because one request returned no suggestions.

## Connections that teach

Keep useful concept relations and their evidence in storage, but omit related-link pills from the reading surface so they do not take space from the notes. If a future connection control is introduced, it should use a specific relation such as **Requires**, **Example of**, **Compare with**, **Used by**, or **Contradicts** and navigate to the exact concept/block. For a contradiction, check whether the claims concern different versions or contexts before treating them as incompatible.

Navigate to the exact concept/block and preserve a Back path. Start with two or three useful connections; a full graph is optional later.

## Boundaries

No “AI” label on every line and no persistent Edit buttons: you have explicitly rejected that clutter. Keep source, revision, and correction details in an inspector. AI can organize and teach, but unsupported generated statements remain proposals until supported; accepting a line does not prove correctness.

Personal thoughts stay verbatim. English, French, and Darija can coexist without unwanted translation. Your Java/backend context helps prioritize examples only when relevant to the selected concept.
