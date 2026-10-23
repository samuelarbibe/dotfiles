#!/opt/homebrew/bin/python3
"""Find failed head pipelines on my open cloud-apps MRs that still need triage.

Orca automation precheck: exit 0 when something needs triage, 1 otherwise.

  red-pipelines.py                  list MRs needing triage (one JSON per line)
  red-pipelines.py mark <pid> <st>  record triage outcome for a pipeline id
                                    st: retried | rebased | notified | handled

A pipeline marked "retried" is listed again if it fails a second time, so the
agent can decide it is not a flake. Every other state silences it for good.
"""

import json
import os
import subprocess
import sys
import urllib.parse
from pathlib import Path

GLAB = "/opt/homebrew/bin/glab"
PROJECT = urllib.parse.quote("prisma-access/prisma-access-browser-group/cloud-apps", safe="")
AUTHOR = "sarbibe"
STATE_FILE = Path.home() / ".local/state/orca-automations/red-pipelines.json"
STATES = {"retried", "rebased", "notified", "handled"}


def read_state() -> dict:
    return json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}


def write_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=1, sort_keys=True))


def fetch_gitlab(path: str):
    out = subprocess.run([GLAB, "api", path], check=True, capture_output=True, text=True, timeout=30)
    return json.loads(out.stdout)


def list_failed_head_pipelines() -> list[dict]:
    mrs = fetch_gitlab(f"projects/{PROJECT}/merge_requests?author_username={AUTHOR}&state=opened&per_page=100")
    failed = []
    for mr in mrs:
        pipeline = fetch_gitlab(f"projects/{PROJECT}/merge_requests/{mr['iid']}").get("head_pipeline") or {}
        if pipeline.get("status") == "failed":
            failed.append({
                "iid": mr["iid"],
                "title": mr["title"],
                "branch": mr["source_branch"],
                "pipeline_id": pipeline["id"],
                "pipeline_url": pipeline.get("web_url"),
            })
    return failed


def list_needing_triage() -> int:
    state = read_state()
    pending = [p for p in list_failed_head_pipelines() if state.get(str(p["pipeline_id"])) in (None, "retried")]
    for p in pending:
        p["previous"] = state.get(str(p["pipeline_id"]))
        print(json.dumps(p))
    return 0 if pending else 1


def mark(pipeline_id: str, outcome: str) -> int:
    if outcome not in STATES:
        sys.exit(f"state must be one of {sorted(STATES)}")
    state = read_state()
    state[pipeline_id] = outcome
    write_state(state)
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["mark"] and len(args) == 3:
        sys.exit(mark(args[1], args[2]))
    if args:
        sys.exit(__doc__)
    sys.exit(list_needing_triage())
