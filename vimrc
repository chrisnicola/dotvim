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

colorscheme vividchalk
set listchars=tab:▸\ ,eol:¬

if has("autocmd")
  filetype plugin indent on
endif 

let blogit_unformat='pandoc --from=html --to=markdown --reference-links'
let blogit_format='pandoc --from=markdown --to=html --no-wrap'

