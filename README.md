Onesimos Vim
<img src="./doc/onesimos-logo.png" width:auto height=128pt align="right"/>
---
![GitHub](https://img.shields.io/github/license/BaksiLi/Onesimos?style=flat-square)
![GitHub release (latest SemVer including pre-releases)](https://img.shields.io/github/v/release/BaksiLi/Onesimos?include_prereleases&style=flat-square)
![GitHub repo size](https://img.shields.io/github/repo-size/BaksiLi/Onesimos?color=yellow&label=size&style=flat-square)
![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-blue?style=flat-square)
[![Contribute](https://img.shields.io/badge/contribute-gray.svg?style=flat-square)](./CONTRIBUTING.md)

<!-- ## About Onesimos -->
**Onesimos** ('helpful', Latinized *Onesimus*) is a Vim configuration.

General configuration has taken account of [sensible.vim](https://github.com/tpope/vim-sensible) which is probably the highest common factor of many configurations. Other configurations, e.g. keymap, are following the principle of [*Convention over configuration*](https://en.wikipedia.org/wiki/Convention_over_configuration).

Any concerns related to this repository can be issued.

## Installation
### Install & Update Script
```bash
wget https://raw.githubusercontent.com/BaksiLi/Onesimos/master/install.sh && bash ./install.sh
```

Use git pull to update.

### Goals
- [ ] Build CI for Linux, use *vader.vim* for testing.
- [ ] Write a doc.
- [ ] Utilize Async technology
  - [x] CompileRun
  - [ ] OpenREPL (range)
- [ ] User configuration interface.
- [ ] Compile Vim automatically.

## Keymaps
The default leader key is `\`.

#### Dotfile
- `<leader>ed` to edit the dotfile while in vim;
- `<leader>sd` to reload dotfile.
- `<leader>h` to view help document.

#### Editing
- `lkj` (insert mode) to change to normal mode.
- `<space>` to fold manually.
- `<C-e>` to expand snippets.

- `<leader>tr` to toggle enable relative numbering.
- `<leader>tp` to toggle rainbow parenthesis.
- `<leader>ti` to toggle indent lines.

- `]a`/`[a` to go to the next/previous lint position.
- `]b`/`[b` to go to the next/previous buffer position.

#### IDE Features
- `<leader>ff` to open fuzzy finder for the current working directory(LeaderF).
- `<leader>fl` to open fuzzy finder for the current file.
- `<leader>fb` to open fuzzy finder for buffers.
- `<leader>ft` to open fuzzy finder for tags.

- `<F2>` to Toggle Tagbar.
- `<F3>` to Toggle File Tree (NERDTree).
- `<F4>` to Open a terminal window REPL for the specific language of the file (Visual Mode will be supported soon).
- `<F5>` to Run or Compile the current file.
- `<F6>` to Format the current file.

## Explained
I have divided the traditional `.vimrc` into several files and folders in order to improve its scalability with more configurations and compatibility with multiple platforms.

<details>
<summary>File Structure</summary>

<!-- by `tree . -L 1` -->
```
.
├── **snippets**
├── **functions**
├── **plugconf**
├── init.vim
├── README.md
└── automated.vim
```

where there are (currently) three folders of differenciated functions and a few config file named `init.vim` (main) and `automated.vim`.

</details>

### init.vim
   This is the main config file, which was inherited from the old vimrc. As you could read from the above, it is acting as the outline of all other `.vim`s.

### automated.vim
   This is where the system test and install prerequisites to support normal functions of plugins.

### ./plugconf
   The configurations of plugins could be found here with their name as the title followed by '.vim'.

### ./functions
   The folder where customised functions are stored.

### ./snippets
   The default folder for storing snippet rules for [UltiSnips](https://github.com/SirVer/ultisnips). The folder under `~/.vim` should be of limited use.

Notice that these folders and files are autoloaded even for the first time your `.vimrc` is sourced. Adding of any new functionalities will not need manual loading as placing them in their corresponding folder should suffice.

## Acknowledgements
Unless otherwise specified, the repository is Copyright BaksiLi, and are licenced under the [MIT Licence](./LICENSE).

Copyright (c) 2020 BaksiLi
