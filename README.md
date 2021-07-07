# Hundredpoints Vim Plugin

This is an [Hundredpoints][https://hundredpoints.io] plugin for Vim.
[GitHub][] and [Vim online][].

## Installation

By default, the plugin requires Node12+ and `npm` installed.

### Install as Vim8 plugin

Install as a Vim 8 plugin. Note `local` can be any name, but some path
element must be present. On Windows, instead of `~/.vim` use
`$VIM_INSTALLATION_FOLDER\vimfiles`.

```shell
mkdir -p ~/.vim/pack/local/start
cd ~/.vim/pack/local/start
git clone https://github.com/hundredpoints/vim.git
```

### Install with [vim-plug][https://github.com/junegunn/vim-plug]

Use vim-plug by adding to your `.vimrc` in your plugin section:

```viml
Plug 'hundredpoints/vim', { 'do': ':HundredpointsUpdate' }
```

Source your `.vimrc` by calling `:source $MYVIMRC`.

Then call `:PlugInstall`.

### Install with [pathogen][https://github.com/tpope/vim-pathogen]

Use pathogen (the git repository of this plugin is
https://github.com/hundredpoints/vim.git)

Run `:HundredpointsUpdate` after updating

### Install with [Vundle][https://github.com/gmarik/vundle.vim]

Use Vundle by adding to your `.vimrc` Vundle plugins section:

```viml
Plugin 'hundredpoints/vim'
```

Then call `:PluginInstall` and `:HundredpointsUpdate`

## Setup

1. Go to [Hundredpoints][https://hundredpoints.io] and create an account.
2. Run `:HundredpointsSetup`. This will download the Hundredpoints commandline tool. Once downloaded it will open your web browser and generate an access token.
3. Paste access token into the prompt.

## License

BSD-3-Clause.
