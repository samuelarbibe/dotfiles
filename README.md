# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

Includes config for [git-spice (gs)](https://github.com/abhinav/git-spice) and [lazygit](https://github.com/jesseduffield/lazygit) — lazygit is configured with custom keybindings for gs stacked branch workflows.

## Packages

| Package | Contents | Target |
|---------|----------|--------|
| `nvim` | [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6 config (Neovim v0.12.2) | `~/.config/nvim` |
| `ghostty` | [Ghostty](https://ghostty.org/) terminal config | `~/.config/ghostty` |
| `herdr` | [herdr](https://herdr.dev) terminal workspace manager for AI coding agents | `~/.config/herdr` |
| `launchd` | macOS launch agents (herdr CPU-load reporter) | `~/Library/LaunchAgents` |
| `lazygit` | [lazygit](https://github.com/jesseduffield/lazygit) config with [gs](https://github.com/abhinav/git-spice) keybindings | `~/Library/Application Support/lazygit` |

## Setup

### Prerequisites

```sh
brew install stow neovim ghostty lazygit git-spice herdr glab
```

### Install

```sh
git clone https://github.com/samuelarbibe/dotfiles ~/.config/dotfiles
cd ~/.config/dotfiles

# ~/.config packages
stow -t ~/.config nvim ghostty herdr

# ~ packages (macOS)
stow -t ~ launchd

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support lazygit

# Load the herdr CPU-load reporter (macOS)
launchctl load ~/Library/LaunchAgents/dev.herdr.cpu-reporter.plist
```

> The `herdr` package tracks `config.toml` and `cpu-reporter.sh`. Its runtime files
> (logs, sockets, `session.json`) live alongside them in `~/.config/herdr` and are
> left untouched by stow.
>
> `cpu-reporter.sh` samples system CPU load and sets the outer terminal window
> title (Ghostty's tab bar) to `<focused workspace> · CPU X%`, so it shows once in
> the tabline instead of the sidebar. The `launchd` package runs it at login; it
> restores herdr's default title on exit. Tune it with `HERDR_CPU_INTERVAL`
> (seconds).
>
> `GITLAB_HOST` is exported in `~/.zshrc` alongside `GITLAB_TOKEN` so `glab`
> defaults to the self-hosted `code.pan.run` instance. Note that `GITLAB_TOKEN`
> overrides glab's stored credentials for *every* host, so gitlab.com calls fail
> with a 401 until it is unset.

### Uninstall

```sh
cd ~/.config/dotfiles

# Unload the herdr CPU-load reporter first (macOS)
launchctl unload ~/Library/LaunchAgents/dev.herdr.cpu-reporter.plist

# ~/.config packages
stow -t ~/.config -D nvim ghostty herdr

# ~ packages (macOS)
stow -t ~ -D launchd

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support -D lazygit
```

### Adding a new package

1. Create `<package>/<dirname>/` inside the dotfiles directory, where `<dirname>` mirrors the path relative to the stow target.
2. Place config files inside.
3. Run `stow -t <target> <package>`.
