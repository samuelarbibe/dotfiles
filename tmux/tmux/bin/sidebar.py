#!/usr/bin/env python3
"""ws sidebar: your tasks, one row each, in the ws chrome.

Runs in the outer "ui" tmux server (WS_UI) and reads the real server
(WS_SOCKET, the "default" socket when empty). Left click switches the attached
client to the task (reopening it when closed); right click opens its menu.
"""

from __future__ import annotations

import os
import select
import shlex
import shutil
import signal
import subprocess
import sys
import termios
import time
import tty
from dataclasses import dataclass

import tasks

UI = os.environ["WS_UI"]
# Never fall back to $TMUX here: inside the chrome it points at the ui server.
MAIN_SOCKET = os.environ.get("WS_SOCKET") or "default"
SELF_PANE = os.environ.get("TMUX_PANE", "")

# herdr one_dark() palette and status colours.
ACCENT, TEXT, SUBTEXT, OVERLAY0, OVERLAY1 = "#61afef", "#abb2bf", "#969ca8", "#5c6370", "#737a87"
ACTIVE_ROW_BG = "#313640"
STATE_COLOR = {"working": "#e5c07b", "blocked": "#e06c75", "done": "#56b6c2", "idle": "#98c379"}
STATE_ICON = {"working": "●", "blocked": "●", "done": "●", "idle": "○"}
PRIORITY = {"blocked": 4, "done": 3, "working": 2, "idle": 1}
RED, YELLOW, GREEN = STATE_COLOR["blocked"], STATE_COLOR["working"], STATE_COLOR["idle"]
TICKET_STATUS_COLOR = {"in progress": YELLOW, "in review": ACCENT, "done": GREEN}
MR_STATUS = {
    "mergeable": ("ready to merge", GREEN),
    "not_approved": ("needs approval", YELLOW),
    "ci_still_running": ("CI running", YELLOW),
    "ci_must_pass": ("CI must pass", RED),
    "conflict": ("conflicts", RED),
    "discussions_not_resolved": ("open threads", YELLOW),
    "need_rebase": ("needs rebase", YELLOW),
    "draft_status": ("draft", OVERLAY1),
    "unchecked": ("checking", OVERLAY1),
    "checking": ("checking", OVERLAY1),
}

PANE_FORMAT = "\t".join(["#{session_name}", "#{@task_id}", "#{@agent}", "#{@agent_state}"])
RESET = "\033[0m"


def fg(color: str, bold: bool = False) -> str:
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    return f"\033[{'1;' if bold else ''}38;2;{r};{g};{b}m"


def bg(color: str) -> str:
    r, g, b = (int(color[i:i + 2], 16) for i in (1, 3, 5))
    return f"\033[48;2;{r};{g};{b}m"


def fit(text: str, width: int) -> str:
    return text if len(text) <= width else text[:max(0, width - 1)] + "…"


def tilde(path: str) -> str:
    home = os.path.expanduser("~")
    return "~" + path[len(home):] if path.startswith(home) else path


# ------------------------------------------------------------------- tmux

@dataclass
class Pane:
    session: str
    task_id: str
    agent: str
    state: str


def run_tmux(args: list[str], socket: str | None) -> list[str]:
    cmd = ["tmux"] + (["-L", socket] if socket else []) + args
    return subprocess.run(cmd, capture_output=True, text=True).stdout.splitlines()


def main_tmux(*args: str) -> list[str]:
    return run_tmux(list(args), MAIN_SOCKET)


def ui_tmux(*args: str) -> list[str]:
    return run_tmux(list(args), UI)


def read_panes() -> list[Pane]:
    return [Pane(*f) for f in (line.split("\t") for line in main_tmux("list-panes", "-a", "-F", PANE_FORMAT))
            if len(f) == 4]


def attach_pane() -> tuple[str, str]:
    """Pane id and tty of the ui pane that holds the inner tmux client."""
    for line in ui_tmux("list-panes", "-F", "#{pane_id} #{pane_tty}"):
        pane_id, tty_name = line.split(" ", 1)
        if pane_id != SELF_PANE:
            return pane_id, tty_name
    return "", ""


def current_session(client_tty: str) -> str:
    for line in main_tmux("list-clients", "-F", "#{client_tty}\t#{session_name}"):
        tty_name, session = line.split("\t")
        if tty_name == client_tty:
            return session
    return ""


# ------------------------------------------------------------------ tasks

_refresh: subprocess.Popen | None = None


def refresh_if_stale(cache: dict) -> bool:
    """Start a background Jira/GitLab fetch when the cache is stale; True while one runs."""
    global _refresh
    if _refresh and _refresh.poll() is None:
        return True
    if not tasks.cache_is_stale(cache, time.time()):
        return False
    _refresh = subprocess.Popen([sys.executable, tasks.__file__, "refresh"],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, start_new_session=True)
    return True


def rollup(states: list[str]) -> str:
    return max(states, key=lambda s: PRIORITY.get(s, 0)) if states else ""


@dataclass
class TaskRow:
    task: tasks.Task
    session: str    # live tmux session, "" when the task is closed
    status: str
    mrs: list
    state: str      # agent state rolled up over the session


@dataclass
class TaskView:
    rows: list[TaskRow]
    refreshing: bool
    error: str


def read_task_view(panes: list[Pane]) -> TaskView:
    cache = tasks.read_json(tasks.CACHE)
    refreshing = refresh_if_stale(cache)
    sessions = {p.session: p.task_id for p in panes}
    try:
        registry = tasks.load_tasks()
    except RuntimeError as exc:
        return TaskView([], refreshing, str(exc))
    rows = []
    for task in registry:
        live = tasks.live_session(task, sessions)
        state = rollup([p.state for p in panes if p.agent and live and p.session == live])
        rows.append(TaskRow(task, live, tasks.task_status(task, cache), tasks.task_mrs(task, cache), state))
    rows.sort(key=lambda r: (-PRIORITY.get(r.state, 0), not r.session, -r.task.created))
    return TaskView(rows, refreshing, cache.get("error", ""))


# ----------------------------------------------------------------- render

class Screen:
    """Rows of styled text plus the click target of each row."""

    def __init__(self, width: int, height: int):
        self.width, self.height = width, height
        self.rows: list[str] = []
        self.targets: list[tuple[str, str] | None] = []

    def add(self, parts: list[tuple[str, str]], row_bg: str = "", target=None) -> None:
        visible = sum(len(text) for _, text in parts)
        pad = " " * max(0, self.width - visible)
        self.rows.append(row_bg + "".join(style + text for style, text in parts) + row_bg + pad + RESET)
        self.targets.append(target)

    def blank_until(self, row: int) -> None:
        while len(self.rows) < row:
            self.add([])


def mr_badge(mr: dict) -> tuple[str, str]:
    if mr["state"] in ("merged", "closed"):
        return mr["state"], GREEN if mr["state"] == "merged" else OVERLAY1
    if mr["conflicts"]:
        return "conflicts", RED
    if mr["draft"]:
        return "draft", OVERLAY1
    if mr["blocked_by_stack"]:
        return "stacked", OVERLAY1
    return MR_STATUS.get(mr["merge_status"], (mr["merge_status"].replace("_", " "), OVERLAY1))


def task_height(row: TaskRow) -> int:
    return 3 + min(len(row.mrs), 3)


def add_task_rows(screen: Screen, row: TaskRow, view_session: str) -> None:
    task, width = row.task, screen.width
    active = bool(row.session) and row.session == view_session
    row_bg = bg(ACTIVE_ROW_BG) if active else ""
    target = ("task", task.id)
    if row.session:
        icon, color = STATE_ICON.get(row.state, "○"), STATE_COLOR.get(row.state, SUBTEXT)
    else:
        icon, color = "◌", OVERLAY0
    label_style = fg(TEXT, True) if active else fg(SUBTEXT if row.session else OVERLAY1)
    status = fit(row.status, 12)
    label = fit(task.label, width - 5 - len(status))
    screen.add([(fg(color), f" {icon} "), (label_style, label),
                ("", " " * max(1, width - 4 - len(label) - len(status))),
                (fg(TICKET_STATUS_COLOR.get(row.status.lower(), OVERLAY0)), status)], row_bg, target)
    detail = tilde(task.path) if task.kind == "free" else task.title
    screen.add([(fg(OVERLAY1 if row.session else OVERLAY0), "   " + fit(detail, width - 4))], row_bg, target)
    for mr in row.mrs[:2]:
        text, mr_color = mr_badge(mr)
        lead = fit(f"   @{mr['author']} " if task.kind == "review" else f"   !{mr['iid']} ", width // 2)
        screen.add([(fg(OVERLAY0), lead), (fg(mr_color), fit(text, width - len(lead) - 1))], row_bg, target)
    if len(row.mrs) > 2:
        screen.add([(fg(OVERLAY0), f"   +{len(row.mrs) - 2} more MRs")], row_bg, target)
    screen.add([], row_bg, target)


def render(screen: Screen, view: TaskView, view_session: str) -> None:
    note, note_color = (("! ", RED) if view.error else ("↻ ", OVERLAY0) if view.refreshing else ("", OVERLAY0))
    screen.add([(fg(TEXT, True), " tasks"), ("", " " * max(1, screen.width - 13 - len(note))),
                (fg(note_color), note), (fg(ACCENT, True), "+ new")], target=("new", ""))
    screen.add([])
    if view.error:
        screen.add([(fg(RED), "   " + fit(view.error, screen.width - 4))])
        screen.add([])
    if not view.rows:
        screen.add([(fg(OVERLAY0), "   no tasks · prefix n")], target=("new", ""))
    for row in view.rows:
        if len(screen.rows) + task_height(row) > screen.height - 1:
            screen.add([(fg(OVERLAY0), f"   +{len(view.rows) - view.rows.index(row)} more")])
            break
        add_task_rows(screen, row, view_session)
    screen.blank_until(screen.height - 1)
    screen.add([("", " " * (screen.width - 1)), (fg(OVERLAY0), "«")], target=("toggle", ""))


# ---------------------------------------------------------------- actions

def tasks_cli(*args: str) -> str:
    return shlex.join([sys.executable, tasks.__file__, *args])


def run_shell(*argv: str) -> str:
    return f"run-shell -b {shlex.quote(shlex.join(argv))}"


def task_menu(row: TaskRow, client_tty: str) -> None:
    """Right-click menu on a task, shown on the main client."""
    task = row.task
    items = ["open", "o", f"run-shell -b {shlex.quote(tasks_cli('open', task.id, '--client', client_tty))}"]
    if task.kind == "ticket":
        items += ["open in Jira", "j", run_shell("open", f"{tasks.effort.JIRA_URL}/browse/{task.ref}")]
    for mr in row.mrs[:3]:
        items += [f"open !{mr['iid']} in GitLab", "", run_shell("open", mr["url"])]
    items += ["", "", "",
              "remove task (keeps worktree and session)", "r",
              f"run-shell -b {shlex.quote(tasks_cli('rm', task.id))}"]
    title = f" {task.label} ".replace("#", "##")  # -T is a format; free-task titles are typed text
    main_tmux("display-menu", "-c", client_tty, "-T", title, "-x", "C", "-y", "C", *items)


def act(target: tuple[str, str], button: int, client_tty: str, ui_attach: str, view: TaskView) -> None:
    kind, value = target
    if kind == "new":
        cwd = main_tmux("display", "-p", "-c", client_tty, "#{pane_current_path}")
        main_tmux("run-shell", "-b", tasks_cli("popup", "--client", client_tty,
                                               "--dir", cwd[0] if cwd else os.path.expanduser("~")))
    elif kind == "task":
        row = next((r for r in view.rows if r.task.id == value), None)
        if not row:
            return
        if button == 2:
            task_menu(row, client_tty)
        elif row.session:
            main_tmux("switch-client", "-c", client_tty, "-t", f"={row.session}")
        else:
            main_tmux("run-shell", "-b", tasks_cli("open", row.task.id, "--client", client_tty))
    elif kind == "toggle":
        ui_tmux("resize-pane", "-Z", "-t", ui_attach)


def parse_clicks(data: str) -> list[tuple[int, int]]:
    """(row, button), 0-based row, of left (0) and right (2) presses in SGR mouse reports."""
    clicks = []
    for chunk in data.split("\033[<")[1:]:
        end = next((i for i, c in enumerate(chunk) if c in "Mm"), -1)
        if end < 0 or chunk[end] != "M":
            continue
        try:
            button, _x, y = (int(v) for v in chunk[:end].split(";"))
        except ValueError:
            continue
        if button in (0, 2):
            clicks.append((y - 1, button))
    return clicks


def main() -> None:
    stdin = sys.stdin.fileno()
    saved = termios.tcgetattr(stdin)
    tty.setcbreak(stdin)
    out = sys.stdout
    out.write("\033[?25l\033[?1000h\033[?1006h\033[2J")
    redraw = {"now": True}
    signal.signal(signal.SIGWINCH, lambda *_: redraw.update(now=True))
    last = ""
    try:
        while True:
            ui_attach, client_tty = attach_pane()
            cols, rows = shutil.get_terminal_size()
            screen = Screen(cols, rows)
            view = read_task_view(read_panes())
            render(screen, view, current_session(client_tty))
            frame = "\033[H" + "\r\n".join(screen.rows[:rows])
            if frame != last or redraw["now"]:
                out.write(frame)
                out.flush()
                last, redraw["now"] = frame, False
            try:
                ready, _, _ = select.select([stdin], [], [], 1.0)
            except InterruptedError:
                continue
            if ready:
                data = os.read(stdin, 1024).decode(errors="ignore")
                for row, button in parse_clicks(data):
                    target = screen.targets[row] if 0 <= row < len(screen.targets) else None
                    if target:
                        act(target, button, client_tty, ui_attach, view)
                        redraw["now"] = True
    finally:
        out.write("\033[?1000l\033[?1006l\033[?25h")
        out.flush()
        termios.tcsetattr(stdin, termios.TCSADRAIN, saved)


if __name__ == "__main__":
    main()
