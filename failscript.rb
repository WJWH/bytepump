require 'bytepump'
require 'socket'
require 'io/nonblock'
s1 = File.new('abc.png','w')  # we'll assume you already got it from somewhere, like a rack hijack or something
#further assume that you have already sent any response headers etc that you want to s1
s1.flush # clear any buffer 
s2 = TCPSocket.new("s3.amazonaws.com",80)
s1.nonblock = true
s2.nonblock = true
#request the page
s2 << "GET /nlga/uploads/item/image/12267/125.png HTTP/1.0\nConnection: keep-alive\n\n"
headers = s2.skip_headers # will read ahead until it encounters a double \r\n, indicating end of headers
p headers
p s2.splice_to(s1, 60) {|b| p b }
s1.close
s2.close