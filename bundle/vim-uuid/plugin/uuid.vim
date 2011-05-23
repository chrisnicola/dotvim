if !has('ruby')
  finish
endif

function s:uuid()
  ruby $uuid.generate
endfunction

command uuid :call <SID>uuid()

ruby << EOF
  # require Ruby files
  begin 
    require 'uuid'
    require 'controller'
    $uuid = VimUUID::Controller.new
  end
EOF
