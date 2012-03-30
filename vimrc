" Plugin Options
let g:AutoPairsShortcutFastWrap = '<C-e>'

let g:syntastic_check_on_open=1
let g:syntastic_auto_jump=1
let g:syntasttic_auto_loc_list=1

" General settings
set nocompatible
set term=xterm-256color
set t_Co=256
set hidden
set number
set tabstop=2
set shiftwidth=2
set smarttab
set expandtab
set cindent
set autoindent
set ruler
set backspace=indent,eol,start
set novisualbell
set noerrorbells
set laststatus=2
set showmatch
set wildmenu
set hidden
set lazyredraw
set ttyfast
let g:CommandTMaxHeight = 20
set wildignore+=*.o,*.obj,.git,*.pyc,log,tmp,*.lock
set clipboard+=unnamed

call pathogen#infect()
call pathogen#helptags()
syntax on
filetype plugin indent on

" Style options
set background=dark
colorscheme solarized
set listchars=tab:▸\ ,eol:¬
set list
set guifont=Meslo\ LG\ S:h13.00

" Custom shortcuts
map <C-f>     :NERDTreeToggle<CR>
map <leader>ss :setlocal spell!<cr>
map <leader>sc :SyntasticCheck<CR>
