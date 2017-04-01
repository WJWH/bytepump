require "bytepump/version"
require "io/nonblock"


module Bytepump
  class IO
    def splice_to(target_io, timeout = 60)
      self.nonblock do |self_nb| #after this, the 
        target_io.nonblock do |target_nb|
          result = self_nb.c_splice_to(target_nb, timeout)
        end
      end
      return result
    end
    
    
end
