require 'uuid'

module VimUUID
  class Controller
    def generate
      VIM::message(UUID.create)
    end
  end
end
