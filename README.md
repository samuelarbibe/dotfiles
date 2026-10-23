# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

Includes config for [git-spice (gs)](https://github.com/abhinav/git-spice) and [lazygit](https://github.com/jesseduffield/lazygit) — lazygit is configured with custom keybindings for gs stacked branch workflows.

## Packages

| Package | Contents | Target |
|---------|----------|--------|
| `nvim` | [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6 config (Neovim v0.12.2) | `~/.config/nvim` |
| `ghostty` | [Ghostty](https://ghostty.org/) terminal config | `~/.config/ghostty` |
| `herdr` | [herdr](https://herdr.dev) terminal workspace manager for AI coding agents | `~/.config/herdr` |
| `tmux` | tmux set up to feel like herdr; `bin/ws` opens it with the spaces/agents sidebar | `~/.config/tmux` |
| `lazygit` | [lazygit](https://github.com/jesseduffield/lazygit) config with [gs](https://github.com/abhinav/git-spice) keybindings | `~/Library/Application Support/lazygit` |
| `uni` | Shared pandoc/LaTeX setup (`pandoc.yaml` defaults file, `macros.tex` preamble) for compiling markdown course notes to PDF | `~/Documents/uni` |

## Setup

### Prerequisites

```sh
brew install stow neovim ghostty lazygit git-spice herdr glab tmux
```

The `uni` package additionally needs pandoc, a LaTeX distribution with `pdflatex`, and `mutool` (for visually checking rendered figures):

```sh
brew install pandoc mupdf
brew install --cask basictex
```

After installing BasicTeX, install the LaTeX packages the notes rely on (tikz/pgf, amsmath, amsthm, xcolor):

```sh
sudo tlmgr update --self
sudo tlmgr install pgf xcolor mathtools
```

### Install

```sh
git clone https://github.com/samuelarbibe/dotfiles ~/.config/dotfiles
cd ~/.config/dotfiles

# ~/.config packages
stow -t ~/.config nvim ghostty herdr tmux
ln -sf ~/.config/tmux/bin/ws ~/.local/bin/ws

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support lazygit

# ~/Documents packages
stow -t ~/Documents/uni uni
ln -sf ~/.config/dotfiles/uni/.gitignore ~/Documents/uni/.gitignore
```

> The `tmux` package runs `ws` from a plain Ghostty tab: an outer tmux server
> (`ui.conf`) holds `bin/sidebar.py` next to a pane attached to the real server
> (`tmux.conf`). The pi extension `~/.pi/agent/extensions/tmux-agent-state.ts`
> reports agent state into pane options. TPM plugins live in `~/.tmux/plugins`
> and resurrect saves in `~/.local/share/tmux/ws-resurrect`, outside the repo.
>
> The `herdr` package tracks `config.toml`. Its runtime files (logs, sockets,
> `session.json`) live alongside it in `~/.config/herdr` and are left untouched
> by stow.
>
> The `uni` package's `.gitignore` is symlinked by hand because stow ignores
> dotfiles matching its own `.gitignore`/`.git` patterns by default.
>
> **One Dark palette.** Three packages theme themselves independently and must be
> kept in sync: `nvim` (onedarkpro.nvim `onedark`), `herdr` (`[theme] name = "one-dark"`)
> and `ghostty` (`themes/one-dark`, a local theme — the bundled *Atom One Dark* uses
> Atom's gutter shade `#21252b` instead of the editor background `#282c34`). The
> shared values are `bg #282c34`, `fg #abb2bf`, `gray #5c6370`, `selection #414858`.
>
> `GITLAB_HOST` is exported in `~/.zshrc` alongside `GITLAB_TOKEN` so `glab`
> defaults to the self-hosted `code.pan.run` instance. Note that `GITLAB_TOKEN`
> overrides glab's stored credentials for *every* host, so gitlab.com calls fail
> with a 401 until it is unset.

### Uninstall

```sh
cd ~/.config/dotfiles

# ~/.config packages
stow -t ~/.config -D nvim ghostty herdr tmux

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support -D lazygit

# ~/Documents packages
stow -t ~/Documents/uni -D uni
rm ~/Documents/uni/.gitignore
```

### Adding a new package

1. Create `<package>/<dirname>/` inside the dotfiles directory, where `<dirname>` mirrors the path relative to the stow target.
2. Place config files inside.
3. Run `stow -t <target> <package>`.
