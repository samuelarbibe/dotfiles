# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

Includes config for [git-spice (gs)](https://github.com/abhinav/git-spice) and [lazygit](https://github.com/jesseduffield/lazygit) — lazygit is configured with custom keybindings for gs stacked branch workflows.

## Packages

| Package | Contents | Target |
|---------|----------|--------|
| `nvim` | [AstroNvim](https://github.com/AstroNvim/AstroNvim) v6 config (Neovim v0.12.2) | `~/.config/nvim` |
| `ghostty` | [Ghostty](https://ghostty.org/) terminal config | `~/.config/ghostty` |
| `tmux` | tmux config (XDG-compliant, requires tmux 3.1+) | `~/.config/tmux` |
| `herdr` | [herdr](https://herdr.dev) terminal workspace manager for AI coding agents | `~/.config/herdr` |
| `lazygit` | [lazygit](https://github.com/jesseduffield/lazygit) config with [gs](https://github.com/abhinav/git-spice) keybindings | `~/Library/Application Support/lazygit` |

## Setup

### Prerequisites

```sh
brew install stow neovim ghostty tmux lazygit git-spice herdr
```

### Install

```sh
git clone https://github.com/samuelarbibe/dotfiles ~/.config/dotfiles
cd ~/.config/dotfiles

# ~/.config packages
stow -t ~/.config nvim ghostty tmux herdr

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support lazygit
```

> The `herdr` package only tracks `config.toml`. Its runtime files (logs, sockets,
> `session.json`) live alongside it in `~/.config/herdr` and are left untouched by stow.

### Uninstall

```sh
cd ~/.config/dotfiles

# ~/.config packages
stow -t ~/.config -D nvim ghostty tmux herdr

# ~/Library/Application Support packages (macOS)
stow -t ~/Library/Application\ Support -D lazygit
```

### Adding a new package

1. Create `<package>/<dirname>/` inside the dotfiles directory, where `<dirname>` mirrors the path relative to the stow target.
2. Place config files inside.
3. Run `stow -t <target> <package>`.
