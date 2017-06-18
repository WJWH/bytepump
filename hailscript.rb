require 'bytepump'
require 'socket'
require 'io/nonblock'
s1 = File.new('abc.png','w')  # we'll assume you already got it from somewhere, like a rack hijack or something

p splice_from_URL(send_socket: s1, host: "s3.amazonaws.com", path: "/nlga/uploads/item/image/12267/125.png", num_to_read: 93323) {|b| p b}
s1.close
