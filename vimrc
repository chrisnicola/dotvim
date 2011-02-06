filetype off

call pathogen#runtime_append_all_bundles()
call pathogen#helptags()

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

if !exists('*Wordpress_vim')
  runtime vimblog.vim
endif

let blogit_unformat='pandoc --from=html --to=markdown --reference-links'
let blogit_format='pandoc --from=markdown --to=html --no-wrap'

