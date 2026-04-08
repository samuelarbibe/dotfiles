# Dotfiles

Personal configuration files managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Packages

| Package | Contents | Target |
|---------|----------|--------|
| `nvim` | [AstroNvim](https://github.com/AstroNvim/AstroNvim) v5+ config | `~/.config/nvim` |
| `ghostty` | [Ghostty](https://ghostty.org/) terminal config | `~/.config/ghostty` |
| `tmux` | tmux config (XDG-compliant, requires tmux 3.1+) | `~/.config/tmux` |

## Setup

### Prerequisites

- [GNU Stow](https://www.gnu.org/software/stow/) (`brew install stow`)
- [lazygit](https://github.com/jesseduffield/lazygit) (`brew install lazygit`)

### Install

```sh
git clone https://github.com/samuelarbibe/vim ~/.config/dotfiles
cd ~/.config/dotfiles
stow -t ~/.config nvim ghostty tmux
```

### Uninstall

```sh
cd ~/.config/dotfiles
stow -t ~/.config -D nvim ghostty tmux
```

### Adding a new package

1. Create `<package>/<dirname>/` inside the dotfiles directory, where `<dirname>` mirrors the path relative to `~/.config/`.
2. Place config files inside.
3. Run `stow -t ~/.config <package>`.
