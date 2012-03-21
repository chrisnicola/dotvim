let g:AutoPairsShortcutFastWrap = '<C-e>'

set term=xterm-256color
set t_Co=256
filetype off
call pathogen#helptags()
call pathogen#runtime_append_all_bundles()
set hidden
set number
set tabstop=2
set smarttab
set shiftwidth=2
set autoindent
set expandtab
set hlsearch
syntax on

set background=dark
colorscheme solarized
set listchars=tab:▸\ ,eol:¬
set list
set guifont=Meslo\ LG\ S:h13.00

if has("autocmd")
  filetype plugin indent on
endif 
set backspace=indent,eol,start
map <leader>ss :setlocal spell!<cr>

let g:CommandTMaxHeight = 20
set wildignore+=*.o,*.obj,.git,*.pyc,log,tmp,*.lock
set clipboard=unnamed
