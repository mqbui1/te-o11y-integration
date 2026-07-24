# Who Should Attend Which Modules

Use this to decide who from your organization needs to be in the room, and where they can tune in/out if the full session doesn't fit their calendar.

## Role → Module Matrix

| Role | Must attend | Can skip | Why |
|------|-------------|----------|-----|
| **Observability / Platform Owner** (workshop sponsor) | All modules | None | Owns the end-to-end story — needs the full picture to scope a POC and decide who else should own what afterward. |
| **SRE / Platform Engineering** | 1, 3, 4, 5, 6, 7 | 2 (can skim) | These are the people who'll actually operate this: deployment footprint (1), TE test config (3), alerting (4), and all three live triage scenarios (5–7) are their day-to-day. |
| **Network Engineering / NetOps** | 1, 3, 5, 6, 7 | 2, 4 | Module 3 is the one built specifically to prove TE's in-cluster vantage point gives them a definitive "not our problem" or "here's the path" answer — fastest way to earn their buy-in. Scenarios 5–7 are where they see that proof in action three different ways. |
| **AI/ML Engineering** (agent developers) | 2, 7 | 3, 4 | Module 2 is the instrumentation pattern they'd actually copy into their own agent code. Module 7 (LLM auth failure) is the single most common failure mode they personally debug — the rest is infrastructure they don't own. |
| **DevOps / Kubernetes Platform Team** | 1, 4 | 5, 6, 7 (can observe passively) | They care about deployment footprint (one collector, no secondary agents) and how alerts plug into existing on-call tooling — not necessarily running each failure scenario themselves. |
| **Incident Commander / On-Call Manager** | 4, 5, 6, 7 | 1, 2, 3 | They want to see what an actual page looks like — alert bodies with embedded triage decision trees — and experience the "who do I call" decision in each scenario. |
| **Security / Compliance / Audit** | 2 | 3, 4, 5, 6, 7 | Module 2 shows what's captured (structured logs, `trace_id` tagging, full exception stack traces) — the evidence story. Note: the standalone log-search/RCA walkthrough isn't part of this run (see Module 8 note) — flag if your compliance team needs to see that live in a follow-up session. |

## Suggested Attendance Patterns

**Option A — Everyone together (recommended for a first session):** Run Modules 0–4 as a full group so everyone shares the same baseline understanding of the system and pipeline, then let Network/NetOps, AI/ML Engineering, and SRE self-select into the scenarios most relevant to them for Modules 5–7, and regroup for Module 8.

**Option B — Role-based breakout after Module 1:** If calendars are tight, only require Module 1 (setup) for everyone, then route people by role using the matrix above, and regroup for Module 8's wrap-up so next steps are decided as a group, not in silos.

**Option C — Leadership-only abbreviated path:** For an executive sponsor who won't run hands-on labs themselves, Modules 0 (Agenda) → 7 (LLM failure — highest business impact) → 8 (Wrap-Up) gives the business case in under 40 minutes without requiring them to touch a terminal.

## A note for the workshop sponsor

The one constant across every role: **make sure whoever owns the Splunk Platform (Splunk Cloud) admin relationship in your organization is looped in before scaling this beyond the workshop.** Log Observer Connect and full log-search RCA (mentioned in Module 8) require that access, and it's the one piece this workshop's shared environment can't demonstrate end-to-end.
