# Morning digest

You run unattended as an Orca automation. Read-only: never comment, approve,
push, retry, post to Slack, or create anything. Your final message becomes an
Orca notification body, which is cut at 180 characters.

## Gather

GitLab user is `sarbibe`, project is `prisma-access/prisma-access-browser-group/cloud-apps`.

1. My open MRs: for each, use `cloud mr status <iid>` (or `glab api`) and put it
   in exactly one bucket:
   - **ready** — approved and pipeline green
   - **needs me** — unresolved threads from someone else, or changes requested
   - **red** — head pipeline failed. Check
     `~/.local/state/orca-automations/red-pipelines.json`: state `notified`
     means triage already found a real failure; `retried`/`rebased` means
     triage is on it — count those as **waiting**, not red
   - **waiting** — everything else
2. Reviews waiting on me: open MRs where I am a reviewer and have not approved.
3. Shipped to production — extension only. Find my MRs merged in the last 14
   days that touch `apps/browser/extension` or `apps/browser/hawkeye`. Using
   the `extension-version` and `check-extension-rollout` skills, decide which
   are contained in the version serving production on the stable channel.
   Skip any MR id already listed in
   `~/.local/state/orca-automations/announced-prod.json` (a JSON array of MR
   iids); append the newly shipped ones to it. Ignore backend and dashboard —
   production can't be verified for those.

If a source fails, say so in the summary in a couple of words rather than
guessing.

## Report

Final message: one line, at most 170 characters, no preamble, no markdown
headers, no ids without a word of what they are. Lead with what needs me.
Omit empty buckets. Example:

`Needs you: passkey MFA (2 threads), 1 review. Red: CloakBrowser e2e. 2 ready to merge. Shipped: TW-55006 passkey flag cleanup.`

If nothing needs me: `All clear — 3 MRs waiting on review, nothing red.`
