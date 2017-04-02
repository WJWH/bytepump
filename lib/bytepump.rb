require "bytepump/version"
require "bytepump/bytepump" # the C file
require "io/nonblock"
require "socket"

#add some methods to IO
class IO
  #skip bytes until you get to the body of the response
  def skip_headers(max_read_size = 4096)
    headers = ""
    until (headers[-3..-1] == "\n\r\n" || headers[-2..-1] == "\n\n" || headers.size >= max_read_size) do
      headers << self.sysread(1)
    end
    return headers
  end
  
#terribly hacky, but it works. TODO: make this better with actual headers and such
def splice_from(host:,path:, timeout: 60)
  s = TCPSocket.new(host,80)
  s << "GET #{path} HTTP/1.0\n\n"
  s.skip_headers
  s.splice_to(self,timeout)
  s.close
end
end