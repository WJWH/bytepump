# THIS README IS OUTDATED AND WILL BE REWRITTEN SOON

## bytepump
A small Ruby gem to efficiently splice the contents of one file descriptor to another, using Linux syscalls.

## What it does
If you have two IO objects that are backed by a file, a socket or a pipe (basically anything with a file descriptor), this gem will define a method `splice_to` that will use the Linux `splice` syscall to copy the contents from one of your IOs to the other, while keeping the actual data copied out of the Ruby VM and so not triggering any GC. As such it works a bit like `IO::copy_stream`, but it always works in a nonblocking way, using a timeout where necessary and optionally calling a block whenever some data is written to the downstream socket.

There are also a few helper methods to make "edge includes" simpler.

## Limitations
* It only works on Linux distributions that have the `splice` syscall. 
* It only works on Ruby version >2.0, due to the GVL escaping funcions used.
* It only works on IO objects that are actually backed by a linux file descriptor. So, a StringIO won't work.
* Most Ruby (and C) methods that deal with IO do a lot of buffering, even on reads. Mixing this gem with most IO methods that read from a socket will lead to unexpected results. IO#sysread should be OK though.
* There is currently not a method that allows for splicing a limited number of bytes, it reads all the way until EOF is reached. Maybe I will add it in a future release.

## Examples
Copying a file:

```Ruby
require 'bytepump'
f1 = File.open 'file1.txt' 
f2 = File.open 'file2.txt' 
f1.splice_to f2 #=> (however many bytes were in file1.txt)
f1.close
f2.close
```

Emulating nonblocking `sendfile`:

```Ruby
require 'bytepump'
require 'socket'
require 'io/nonblock'
s = ... # we'll assume you already got it from somewhere, like a rack hijack or something
s.nonblock = true
f = File.open 'file1.txt'
f.nonblock = true
#every time some bytes were sent, the block will be called with the amount of bytes.
#if the downstream socket slowlorises and doesn't download any bytes for 60 seconds, this will
#return :timeout_downstream, otherwise it will return the total number of bytes sent
f.splice_to(s, 60) {|b| report_that_some_bytes_were_sent(b) } 
f.close
s.close
```

Very simple edge include: a picture of Matz

```Ruby
require 'bytepump'
require 'socket'
require 'io/nonblock'
s1 = ... # we'll assume you already got it from somewhere, like a rack hijack or something
#further assume that you have already sent any response headers etc that you want to s1
s1.flush # clear any buffer 
s2 = TCPSocket "s3.amazonaws.com",80
s1.nonblock = true
s2.nonblock = true
#request the page
s2 << "GET /nlga/uploads/item/image/12267/125.png HTTP/1.0\n\n"
s2.skip_headers # will read ahead until it encounters a double \r\n, indicating end of headers
s2.splice_to(s1, 60) #you can also leave the block and it will not report its progress
s1.close
s2.close
```

Slightly more involved example: Put together a custom zip archive from S3 objects using Wetransfers' ZipTricks library.

```Ruby
require 'bytepump'
require 'socket'
require 'io/nonblock'
require 'zlib'
require 'zip_tricks'
#socket to the user
s = ... # we'll assume you already got it from somewhere, like a rack hijack or something
s.flush
s.nonblock = true
#assume that you have some Enumerable s3_objects that contains the data about the files 
#that should go into the archive. We'll just assume they're all STORED entries for simplicity,
#but allowing for DEFLATEd objects is trivial
ZipTricks::Streamer.open(s) do | zip |
    s3_objects.each do |obj|
        zip.add_stored_entry(filename: obj.filename, size: obj.filename, crc32: obj.crc32)
        #you will need to set your bucket permissions right for this
        s.flush #'normal' Ruby IO is heavily buffered and doesn't play well with bytepump
        bytes_written = s.splice_from(host: s3_url, path: obj.s3_path) {|b| report_bytes_sent(b)}
        zip.simulate_write(bytes_written)
    end
end #ending the block will cause the central directory for the archive to be written
s.close
```
    
## Contributing
Please feel free to contribute with patches, issues or feature requests! 
