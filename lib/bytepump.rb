require "bytepump/version"
require "bytepump/bytepump" # the C file
require "io/nonblock"

#add some methods to IO
class IO
  def splice_to(target_io, timeout = 60)
    # define result here to broaden the variable scope, otherwise it would only be accessible in the block
    result = nil 
    self.nonblock do |self_nb| #after the block, the original blocking state will be restored
      target_io.nonblock do |target_nb|
        result = self_nb.c_splice_to(target_nb, timeout)
      end
    end
    return result #error here??
  end
    
end