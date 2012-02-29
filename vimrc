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
syntax on

set background=dark
let g:solarized_termcolors=16
colorscheme solarized
set listchars=tab:▸\ ,eol:¬
set guifont="Meslo LG S":h13.00

if has("autocmd")
  filetype plugin indent on
endif 

map <leader>ss :setlocal spell!<cr>
