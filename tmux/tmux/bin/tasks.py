#!/usr/bin/env python3
"""Tasks: workspaces you create by hand, linked to Jira and GitLab automatically.

A task is one of
  ticket  TW-55006   worktree on the ticket's branch; Jira status and MRs attach
  review  !39426     detached worktree on the MR's source branch; MR state attaches
  free    any name   a session in a directory you pick; nothing attaches
Tasks are kept in STATE and outlive their tmux session: opening a closed task
recreates the session and resumes its pi session. Jira and GitLab facts are
cached in CACHE and refreshed in the background once older than STALE_AFTER.

  tasks.py popup --client TTY --dir DIR   open the new-task dialog in a popup
  tasks.py new --client TTY --dir DIR     the dialog itself
  tasks.py open ID [--client TTY]         switch to the task, reopening it if closed
  tasks.py rm ID                          forget the task (worktree and session stay)
  tasks.py refresh | list
"""

from __future__ import annotations

import argparse
import fcntl
import importlib.machinery
import importlib.util
import json
import os
import re
import select
import shlex
import subprocess
import sys
import termios
import time
import tty
import uuid
from contextlib import contextmanager
from dataclasses import asdict, dataclass, field
from pathlib import Path

REPO = os.environ.get("WS_TASK_REPO", str(Path.home() / "Documents/Workspace/cloud-apps"))
REVIEWS_DIR = str(Path(REPO).parent / "reviews")
STATE = Path(os.environ.get("WS_TASK_STATE", Path.home() / ".local/state/ws/tasks.json"))
CACHE = Path(os.environ.get("WS_TASK_CACHE", Path.home() / ".cache/ws/tasks.json"))
STALE_AFTER = 60
EFFORT = Path.home() / ".local/bin/effort"


def load_effort():
    """Jira/GitLab fetching and the branch conventions live in `effort`; reuse them."""
    loader = importlib.machinery.SourceFileLoader("effort", str(EFFORT))
    spec = importlib.util.spec_from_loader("effort", loader)
    module = importlib.util.module_from_spec(spec)
    sys.modules["effort"] = module  # dataclasses look the module up while it loads
    loader.exec_module(module)
    return module


effort = load_effort()


@dataclass
class Task:
    id: str
    kind: str                 # ticket | review | free
    ref: str                  # TW-55006 | 39426 | ""
    title: str
    path: str
    session: str
    branch: str = ""
    agent_id: str = ""        # pi --session-id, set when an agent was started
    created: float = field(default_factory=time.time)

    @property
    def label(self) -> str:
        return {"ticket": self.ref, "review": f"!{self.ref}"}.get(self.kind, self.title)


# ----------------------------------------------------------------- registry

def write_json(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(f".tmp.{os.getpid()}")  # several writers can race
    tmp.write_text(json.dumps(data, indent=1))
    tmp.replace(path)


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def load_tasks(path: Path = STATE) -> list[Task]:
    """Raises on a damaged file, so a writer never overwrites tasks it couldn't read."""
    try:
        return [Task(**t) for t in json.loads(path.read_text())["tasks"]]
    except FileNotFoundError:
        return []
    except (json.JSONDecodeError, KeyError, TypeError) as exc:
        raise RuntimeError(f"{path} is damaged ({exc}); fix or move it") from exc


@contextmanager
def registry_lock(path: Path = STATE):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path.with_suffix(".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield


def save_tasks(tasks: list[Task], path: Path = STATE) -> None:
    write_json(path, {"tasks": [asdict(t) for t in tasks]})


def add_task(task: Task, path: Path = STATE) -> None:
    with registry_lock(path):
        tasks = load_tasks(path)
        if any(t.id == task.id for t in tasks):
            raise RuntimeError(f"task {task.label} already exists")
        save_tasks([*tasks, task], path)


def remove_task(task_id: str, path: Path = STATE) -> None:
    with registry_lock(path):
        tasks = load_tasks(path)
        if not any(t.id == task_id for t in tasks):
            raise RuntimeError(f"no task {task_id}")
        save_tasks([t for t in tasks if t.id != task_id], path)


def find_task(task_id: str, path: Path = STATE) -> Task:
    task = next((t for t in load_tasks(path) if t.id == task_id), None)
    if not task:
        raise RuntimeError(f"no task {task_id}")
    return task


# ------------------------------------------------------------- remote facts

def slim_mr(mr: dict) -> dict:
    return {
        "iid": mr["iid"], "url": mr.get("web_url", ""), "title": mr.get("title", ""),
        "source": mr["source_branch"], "target": mr["target_branch"],
        "author": (mr.get("author") or {}).get("username", ""), "state": mr.get("state", ""),
        "draft": mr.get("draft", False), "merge_status": mr.get("detailed_merge_status", ""),
        "conflicts": mr.get("has_conflicts", False),
        "blocked_by_stack": mr.get("blocked_by_stack", False), "ticket": mr.get("ticket", ""),
    }


def project_api(repo: str) -> str:
    return "projects/" + effort.project_path(repo).replace("/", "%2F")


def summary_from_mr_title(title: str) -> str:
    """`type(scope): TW-123 | text` -> `text`."""
    return title.split("|", 1)[1].strip() if "|" in title else title


def fetch_mr(repo: str, iid: str) -> dict:
    mr = effort.glab_api(f"{project_api(repo)}/merge_requests/{iid}", repo)
    if not mr:
        raise RuntimeError(f"could not read MR !{iid}")
    return slim_mr(mr)


def fetch_remote(repo: str, tasks: list[Task]) -> dict:
    """Sprint issues, my open MRs, and the issues and MRs the tasks point at.
    Failure comes back as {"error": ...} so the last good facts stay usable."""
    try:
        sprint = effort.fetch_sprint()
        mrs = [slim_mr(m) for m in effort.fetch_my_mrs(repo)]
    except SystemExit as exc:
        return {"error": str(exc)}
    issues = {i["key"]: i for i in sprint}
    for t in tasks:
        if t.kind == "ticket" and t.ref not in issues:
            summary, status = effort.fetch_jira(t.ref)
            issues[t.ref] = {"key": t.ref, "summary": summary, "status": status, "priority": ""}
    reviews = {}
    for t in tasks:
        if t.kind == "review":
            try:
                reviews[t.ref] = fetch_mr(repo, t.ref)
            except RuntimeError:
                pass
    return {"issues": issues, "sprint": [i["key"] for i in sprint], "mrs": mrs, "reviews": reviews}


def refresh_cache(repo: str = REPO, path: Path = CACHE) -> dict:
    fetched = fetch_remote(repo, load_tasks())
    data = {**read_json(path), **fetched, "fetched_at": time.time()}
    if "error" not in fetched:
        data.pop("error", None)
    write_json(path, data)
    return data


def mark_cache_stale(path: Path = CACHE) -> None:
    write_json(path, {**read_json(path), "fetched_at": 0})


def cache_is_stale(cache: dict, now: float) -> bool:
    return now - cache.get("fetched_at", 0) > STALE_AFTER


# ---------------------------------------------------------- derived (links)

def task_mrs(task: Task, cache: dict) -> list[dict]:
    if task.kind == "review":
        mr = cache.get("reviews", {}).get(task.ref)
        return [mr] if mr else []
    if task.kind == "ticket":
        return [m for m in cache.get("mrs", [])
                if m["ticket"] == task.ref or (task.branch and m["source"] == task.branch)]
    return []


def task_status(task: Task, cache: dict) -> str:
    if task.kind == "ticket":
        return cache.get("issues", {}).get(task.ref, {}).get("status", "")
    if task.kind == "review":
        mr = cache.get("reviews", {}).get(task.ref, {})
        state = mr.get("state", "")
        return state if state not in ("", "opened") else "review"
    return ""


def live_session(task: Task, sessions: dict[str, str]) -> str:
    """`sessions` maps session name -> its @task_id. The tag survives renames;
    the stored name covers sessions tmux-resurrect recreated without the tag."""
    tagged = next((name for name, tid in sessions.items() if tid == task.id), "")
    return tagged or (task.session if sessions.get(task.session) == "" else "")


# -------------------------------------------------------------- local facts

def git(*args: str, cwd: str = REPO) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True)


@dataclass
class Worktree:
    path: str
    branch: str


def read_worktrees(repo: str = REPO) -> list[Worktree]:
    """Linked worktrees on a branch. Git lists the main checkout first; skip it."""
    out = git("worktree", "list", "--porcelain", cwd=repo).stdout
    found, path = [], ""
    for block in out.split("\n\n")[1:]:
        if "\nprunable" in block:
            continue
        for line in block.splitlines():
            if line.startswith("worktree "):
                path = line.split(" ", 1)[1]
            elif line.startswith("branch "):
                found.append(Worktree(path, line.split(" ", 1)[1].removeprefix("refs/heads/")))
    return found


def main_tmux(*args: str) -> subprocess.CompletedProcess:
    socket = os.environ.get("WS_SOCKET")
    cmd = ["tmux", *(["-L", socket] if socket else []), *args]
    return subprocess.run(cmd, capture_output=True, text=True)


def read_sessions() -> dict[str, str]:
    out = main_tmux("list-sessions", "-F", "#{session_name}\t#{@task_id}").stdout
    return dict(line.split("\t", 1) for line in out.splitlines() if "\t" in line)


# ---------------------------------------------------------------- worktrees

def slugify(text: str, words: int) -> str:
    return "-".join(re.findall(r"[a-z0-9]+", text.lower())[:words])


def ticket_of_branch(branch: str, mrs: list[dict]) -> str:
    for mr in mrs:
        if mr["source"] == branch and mr["ticket"]:
            return mr["ticket"]
    match = effort.BRANCH_RE.match(branch)
    return match.group("ticket").upper() if match else ""


def default_branch(key: str, summary: str, issue_type: str, mrs: list[dict]) -> str:
    """The top of the ticket's MR stack, else a new type/tw-NNNNN/slug name."""
    mine = [m for m in mrs if m["ticket"] == key]
    targets = {m["target"] for m in mine}
    tops = [m["source"] for m in mine if m["source"] not in targets]
    if tops:
        return tops[0]
    kind = "fix" if issue_type.lower() == "bug" else "feat"
    return f"{kind}/{key.lower()}/{slugify(summary, 5) or 'work'}"


def free_path(path: str) -> str:
    return path if not os.path.exists(path) else f"{path}-{uuid.uuid4().hex[:4]}"


def remote_branch_exists(repo: str, branch: str) -> bool:
    """Raises when origin can't be asked: offline must not read as 'no such branch'."""
    result = git("ls-remote", "--exit-code", "--heads", "origin", branch, cwd=repo)
    if result.returncode not in (0, 2):
        raise RuntimeError(f"cannot reach origin: {result.stderr.strip()}")
    return result.returncode == 0


def fetch(repo: str, branch: str) -> None:
    result = git("fetch", "origin", branch, cwd=repo)
    if result.returncode != 0:
        raise RuntimeError(f"git fetch origin {branch} failed: {result.stderr.strip()}")


def base_ref(repo: str) -> str:
    head = git("symbolic-ref", "--short", "refs/remotes/origin/HEAD", cwd=repo).stdout.strip()
    return head or "origin/master"


def checked_out(result: subprocess.CompletedProcess, path: str) -> str:
    if result.returncode != 0:
        raise RuntimeError(f"git worktree add failed: {result.stderr.strip()}")
    return path


def add_branch_worktree(repo: str, branch: str) -> str:
    """Existing local or remote branch, else a new one cut from the remote default branch."""
    path = free_path(f"{repo}-{slugify(branch.rsplit('/', 1)[-1], 4)}")
    if git("rev-parse", "--verify", "--quiet", f"refs/heads/{branch}", cwd=repo).returncode == 0:
        return checked_out(git("worktree", "add", path, branch, cwd=repo), path)
    if remote_branch_exists(repo, branch):
        fetch(repo, branch)
        return checked_out(git("worktree", "add", path, branch, cwd=repo), path)
    base = base_ref(repo)
    fetch(repo, base.removeprefix("origin/"))
    return checked_out(git("worktree", "add", "--no-track", "-b", branch, path, base, cwd=repo), path)


def add_review_worktree(repo: str, reviews_dir: str, mr: dict) -> str:
    """Detached, so reviewing never creates or moves a local branch."""
    path = free_path(f"{reviews_dir}/{mr['iid']}-{slugify(summary_from_mr_title(mr['title']), 4)}")
    fetch(repo, mr["source"])
    return checked_out(git("worktree", "add", "--detach", path, f"origin/{mr['source']}", cwd=repo), path)


# ----------------------------------------------------------------- sessions

def free_session_name(name: str) -> str:
    taken = set(read_sessions())
    return next(n for n in [name, *(f"{name}-{i}" for i in range(2, 100))] if n not in taken)


def start_session(task: Task, resume: bool, prompt: str = "") -> str:
    """Create the task's tmux session and, when it has an agent, start pi in it."""
    if not os.path.isdir(task.path):
        raise RuntimeError(f"{task.path} no longer exists")
    # Reopening uses the stored name: a second click racing the first then
    # finds it taken and switches, instead of starting a second pi on the same id.
    name = task.session if resume else free_session_name(task.session)
    result = main_tmux("new-session", "-d", "-s", name, "-c", task.path)
    if resume and "duplicate session" in result.stderr:
        return name
    if result.returncode != 0:
        raise RuntimeError(f"tmux new-session failed: {result.stderr.strip()}")
    main_tmux("set", "-t", f"={name}:", "@task_id", task.id)
    if task.agent_id and (prompt or resume):
        cmd = ["pi", "--session-id", task.agent_id, *(["--", prompt] if prompt else [])]
        main_tmux("send-keys", "-t", f"={name}:", shlex.join(cmd), "Enter")
    return name


def switch_to(session: str, client: str | None) -> None:
    main_tmux("switch-client", *(["-c", client] if client else []), "-t", f"={session}")


def forget_task(task_id: str) -> None:
    """Drop the task; its worktree and session stay, untagged so a new task can't inherit them."""
    task = find_task(task_id)
    remove_task(task_id)
    if session := live_session(task, read_sessions()):
        main_tmux("set", "-u", "-t", f"={session}:", "@task_id")


def open_task(task_id: str, client: str | None) -> None:
    task = find_task(task_id)
    session = live_session(task, read_sessions()) or start_session(task, resume=True)
    switch_to(session, client)


# ------------------------------------------------------------------- create

def new_ticket_task(key: str, branch: str, title: str, prompt: str, repo: str = REPO) -> Task:
    """Reuses a worktree already on the branch; otherwise checks the branch out."""
    existing = next((w for w in read_worktrees(repo) if w.branch == branch), None)
    path = existing.path if existing else add_branch_worktree(repo, branch)
    return Task(id=key.lower(), kind="ticket", ref=key, title=title, path=path,
                session=key.lower(), branch=branch, agent_id=str(uuid.uuid4()) if prompt else "")


def new_review_task(mr: dict, prompt: str, repo: str = REPO, reviews_dir: str = REVIEWS_DIR) -> Task:
    path = add_review_worktree(repo, reviews_dir, mr)
    return Task(id=f"review-{mr['iid']}", kind="review", ref=str(mr["iid"]), title=summary_from_mr_title(mr["title"]),
                path=path, session=f"review-{mr['iid']}", branch=mr["source"],
                agent_id=str(uuid.uuid4()) if prompt else "")


def new_free_task(name: str, path: str, cwd: str, prompt: str) -> Task:
    slug = slugify(name, 4) or "task"
    return Task(id=f"{slug}-{uuid.uuid4().hex[:6]}", kind="free", ref="", title=name,
                path=os.path.abspath(os.path.join(cwd, os.path.expanduser(path))), session=slug,
                agent_id=str(uuid.uuid4()) if prompt else "")


def create_task(task: Task, prompt: str, client: str | None) -> None:
    session = start_session(task, resume=False, prompt=prompt)
    task.session = session
    add_task(task)
    mark_cache_stale()
    switch_to(session, client)


# ------------------------------------------------------------------- dialog

TICKET_INPUT = re.compile(r"^(tw-\d+)$", re.I)
MR_INPUT = re.compile(r"^!(\d+)$|merge_requests/(\d+)")


class Cancelled(Exception):
    pass


def utf8_length(lead: int) -> int:
    return 4 if lead >= 0xF0 else 3 if lead >= 0xE0 else 2 if lead >= 0xC0 else 1


def ask(question: str, prefill: str = "") -> str:
    """One editable line, prefilled. Enter accepts; Esc or Ctrl-C raises Cancelled.
    Hand-rolled because macOS Python's libedit can neither prefill nor cancel on Esc."""
    fd, prompt, line = sys.stdin.fileno(), f"  {question}", list(prefill)
    saved = termios.tcgetattr(fd)
    tty.setraw(fd)
    try:
        while True:
            sys.stdout.write(f"\r\033[K{prompt}{''.join(line)}")
            sys.stdout.flush()
            ch = os.read(fd, 1)
            if ch in (b"\r", b"\n"):
                return "".join(line).strip()
            if ch == b"\x03":
                raise Cancelled
            if ch == b"\x1b":
                if not select.select([fd], [], [], 0.05)[0]:
                    raise Cancelled
                os.read(fd, 32)  # arrow or function key: not supported, drop it
            elif ch in (b"\x7f", b"\x08"):
                line = line[:-1]
            elif ch == b"\x15":
                line = []
            elif ch >= b" ":
                rest = os.read(fd, utf8_length(ch[0]) - 1) if ch[0] >= 0xC0 else b""
                line.append((ch + rest).decode(errors="ignore"))
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, saved)
        sys.stdout.write("\r\n")


def sprint_suggestions(cache: dict, tasks: list[Task]) -> list[dict]:
    taken = {t.ref for t in tasks if t.kind == "ticket"}
    issues = cache.get("issues", {})
    return [issues[k] for k in cache.get("sprint", [])
            if k in issues and k not in taken
            and issues[k]["status"].lower() not in effort.DEAD_STATUSES]


def run_dialog(client: str | None, cwd: str) -> None:
    cache, tasks = read_json(CACHE), load_tasks()
    suggestions = sprint_suggestions(cache, tasks)
    print("\n  \033[1mNew task\033[0m\n")
    for i, issue in enumerate(suggestions, 1):
        print(f"   {i:>2}  {issue['key']:10} {issue['status'][:12]:12} {issue['summary'][:48]}")
    if suggestions:
        print()
    print("  \033[2mticket TW-123 or a number above · review !123 or MR url · anything else is a free task\033[0m")
    print("  \033[2mesc cancels\033[0m\n")
    answer = ask("> ")
    if not answer:
        return
    if answer.isdigit() and 1 <= int(answer) <= len(suggestions):
        answer = suggestions[int(answer) - 1]["key"]

    existing = {t.id for t in tasks}
    if m := TICKET_INPUT.match(answer):
        key = m.group(1).upper()
        if key.lower() in existing:
            raise RuntimeError(f"{key} is already a task")
        issue = cache.get("issues", {}).get(key)
        summary = issue["summary"] if issue else effort.fetch_jira(key)[0]
        print(f"  {key}  {summary}")
        branch = ask("branch: ", default_branch(key, summary, (issue or {}).get("type", ""),
                                                  cache.get("mrs", [])))
        prompt = ask("prompt for pi (optional): ")
        print("  \033[2mpreparing worktree…\033[0m", flush=True)
        task = new_ticket_task(key, branch, summary, prompt)
    elif m := MR_INPUT.search(answer):
        iid = m.group(1) or m.group(2)
        if f"review-{iid}" in existing:
            raise RuntimeError(f"!{iid} is already a task")
        mr = fetch_mr(REPO, iid)
        print(f"  !{mr['iid']}  {mr['title']}  by {mr['author']}")
        prompt = ask("prompt for pi (optional): ")
        print("  \033[2mfetching and checking out the MR…\033[0m", flush=True)
        task = new_review_task(mr, prompt)
    else:
        path = ask("directory: ", cwd)
        prompt = ask("prompt for pi (optional): ")
        task = new_free_task(answer, path, cwd, prompt)
    create_task(task, prompt, client)


def open_popup(client: str, cwd: str) -> None:
    cmd = shlex.join([sys.executable, __file__, "new", "--client", client, "--dir", cwd])
    main_tmux("display-popup", "-c", client, "-E", "-w", "100", "-h", "24",
              "-T", " new task ", cmd)


# ---------------------------------------------------------------------- cli

def print_tasks() -> None:
    cache, sessions = read_json(CACHE), read_sessions()
    for t in load_tasks():
        live = live_session(t, sessions)
        print(f"{t.id:22} {t.kind:6} {t.label:12} {task_status(t, cache) or '-':12} "
              f"{'live:' + live if live else 'closed'}  {t.title[:50]}")
        print(f"    {t.path}")
        for mr in task_mrs(t, cache):
            print(f"    !{mr['iid']} {mr['merge_status']} -> {mr['target']}")


def main() -> None:
    ap = argparse.ArgumentParser(prog="tasks.py")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("popup", "new"):
        p = sub.add_parser(name)
        p.add_argument("--client", required=True)
        p.add_argument("--dir", default=str(Path.home()))
    op = sub.add_parser("open")
    op.add_argument("id")
    op.add_argument("--client")
    sub.add_parser("rm").add_argument("id")
    sub.add_parser("refresh")
    sub.add_parser("list")
    args = ap.parse_args()

    try:
        if args.cmd == "popup":
            open_popup(args.client, args.dir)
        elif args.cmd == "new":
            run_dialog(args.client, args.dir)
        elif args.cmd == "open":
            open_task(args.id, args.client)
        elif args.cmd == "rm":
            forget_task(args.id)
        elif args.cmd == "refresh":
            if err := refresh_cache().get("error"):
                sys.exit(err)
        else:
            print_tasks()
    except (Cancelled, KeyboardInterrupt, EOFError):
        sys.exit(0)
    except RuntimeError as exc:
        if args.cmd == "new":  # inside the popup: let the message be read
            print(f"\n  \033[31m{exc}\033[0m")
            input("  press enter to close")
            sys.exit(1)
        if getattr(args, "client", None):  # from run-shell: nobody reads stderr
            main_tmux("display-message", "-c", args.client, "-d", "8000", f"tasks: {exc}")
        sys.exit(str(exc))


if __name__ == "__main__":
    main()
