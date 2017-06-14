require 'bytepump'
require 'socket'
require 'io/nonblock'
s1 = File.new('abc.png','w')  # we'll assume you already got it from somewhere, like a rack hijack or something

p splice_from_URL(s1, "s3.amazonaws.com", "/nlga/uploads/item/image/12267/125.png", 93323) {|b| p b}
s1.close
