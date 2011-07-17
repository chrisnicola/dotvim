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

colorscheme solarized
set background=dark
set listchars=tab:▸\ ,eol:¬
set guifont=Menlo:h13.00

if has("autocmd")
  filetype plugin indent on
endif 

let VIMPRESS = [{'username':'chrisn', 'blog_url':'http://lucisferre.net/'}]

