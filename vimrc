let mapleader=','
let g:mapleader=','
" Plugin Options
let g:AutoPairsShortcutFastWrap = '<C-e>'
let g:syntastic_auto_jump=1
let g:syntastic_auto_loc_list=1

" General settings
set hls
set autoread
set nocompatible
set term=xterm-256color
set t_Co=256
set hidden
set number
set tabstop=2
set shiftwidth=2
set smarttab
set expandtab
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
set wildignore+=*.o,*.obj,.git,*.pyc,log,tmp,*.jpg,*.png,*.gif
set title
" We dont need no stinkin' backup or swap files. We use git!
set nobackup
set noswapfile
" Improve tab completion, works more like bash completion this way
set wildmenu
set wildmode=list:longest
set clipboard=unnamed

call pathogen#infect()
call pathogen#helptags()
syntax on
filetype plugin indent on

" Style options
set background=light
colorscheme solarized
"colorscheme vividchalk
set listchars=tab:▸\ ,eol:¬
set list
set guifont=Meslo\ LG\ S:h13.00

" Custom shortcuts
map <C-f>         :NERDTreeToggle<CR>
map <leader>ss    :setlocal spell!<cr>
map <leader>sc    :SyntasticCheck<CR>
nmap <silent> <leader>ev :e $MYVIMRC<CR>
nmap <silent> <leader>sv :so $MYVIMRC<CR>
map <space> :noh<cr>
" Format paragraphs quickly
vmap Q gq
nmap Q gqap
" Easy window navigation
map <C-h> <C-w>h
map <C-j> <C-w>j
map <C-k> <C-w>k
map <C-l> <C-w>l
" Sudo save me a file (and make me a sandwich)
cmap w!! w !sudo tee % >/dev/null
map <leader>rr    :checktime<CR>
