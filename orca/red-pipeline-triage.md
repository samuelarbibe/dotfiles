# Red pipeline triage

You run unattended as an Orca automation. Your final message becomes an Orca
notification body, cut at 180 characters. Never edit code, never comment on an
MR, never create branches, MRs or worktrees, never post to Slack.

## 1. List

Run `~/.config/dotfiles/orca/red-pipelines.py`. Each output line is a JSON MR
with a failed head pipeline. `previous: "retried"` means it was already retried
once and failed again. No output means nothing to do — finish with
`Nothing red.`

## 2. Classify each one

Read the failed jobs and their logs (`cloud mr ci <iid>`, `glab api`). For E2E
jobs use the `e2e-debugging` skill (Currents history, traces).

- **Flake** — runner/system failure, timeout, network or registry error, or a
  test with a flaky history in Currents that is unrelated to the MR diff.
- **Behind master** — the failure comes from code the MR does not touch and
  master has since changed it (the same job is green on master's latest
  pipeline, a conflict, a fix landed on master).
- **Real** — caused by the MR diff. Also: anything with `previous: "retried"`
  that fails again in the same job.

When unsure, treat it as real.

## 3. Act

Record every outcome with
`~/.config/dotfiles/orca/red-pipelines.py mark <pipeline_id> <state>`.

- **Flake** (only when `previous` is null): retry the failed jobs with
  `glab api -X POST "projects/prisma-access%2Fprisma-access-browser-group%2Fcloud-apps/pipelines/<id>/retry"`,
  then mark `retried`.
- **Behind master**: rebase with git-spice (below), then mark `rebased`.
- **Real**: mark `notified`.

### Rebasing

1. Find the worktree that holds the branch: `orca worktree list`, then
   `git -C <path> branch --show-current` and `git-spice ls` there. If no
   worktree holds the branch or its stack, don't rebase — mark `notified`.
2. Skip without marking (the next run retries) if the worktree has local
   changes (`git status --porcelain` is non-empty) or an agent is working in it
   (`orca worktree ps`).
3. In that worktree, remember the current branch, then run every git-spice
   command as
   `GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true git-spice --no-prompt <cmd>`:
   - `repo sync`
   - `upstack restack --branch=<branch>` — restacks the branch and what sits
     above it, never what sits below.
   - Only if the fix the branch needs has not reached its base because a
     branch below it is itself behind master, use `stack restack` instead.
   - Submit what you restacked: `upstack submit --branch=<branch> --update-only`,
     or `stack submit --update-only` only if you had to restack downstack.
     Run with `--dry-run` first and make sure no branch below the failing one
     would be pushed unless you restacked it on purpose.
4. Check out the remembered branch again.
5. On any conflict or git-spice error: `git-spice rebase abort`, check out the
   remembered branch, mark `notified`, and say why in the report.

Never run `git rebase`, `git push`, or `git push --force` directly.

## 4. Report

Final message: one line, at most 170 characters. Start with `🔴 Needs you:` if
anything was marked `notified`, otherwise `✅ Handled:`. Name each MR by a few
words of its title, not just its id. Example:

`🔴 Needs you: passkey MFA unit test fails on your diff. ✅ CloakBrowser e2e retried (flaky runner).`
