require 'bytepump/version'
require 'bytepump/bytepump' # the C file
require 'io/nonblock'
require 'socket'
require 'io/splice'

# add some methods to IO
class IO
  # skip bytes until you get to the body of the response
  def skip_headers(max_read_size = 4096)
    headers = ''
    until headers[-3..-1] == "\n\r\n" ||
          headers[-2..-1] == "\n\n" ||
          headers.size >= max_read_size
      headers << sysread(1)
    end
    raise "non-200 response received" if headers[0,15] != "HTTP/1.1 200 OK"
    headers
  end
end

def splice_from_URL(send_socket, host, path, num_to_read)
  block_size = 4096 # default kernel buffer size on linux is 65536
  flags = IO::Splice::F_MOVE | IO::Splice::F_MORE
  timeout = 60

  # generate socket to S3
  recv_socket = TCPSocket.new(host,80)
  recv_socket.nonblock = true
  recv_socket << "GET #{path} HTTP/1.1\nHost:#{host}\nConnection: keep-alive\n\n"
  recv_socket.skip_headers
  recv_socket.nonblock = true

  send_socket.nonblock = true

  recv_socket_fd = recv_socket.fileno
  send_socket_fd = send_socket.fileno

  sent_so_far = 0
  read_so_far = 0
  bytes_in_buffer = 0
  pipe = IO.pipe
  rfd, wfd = pipe.map { |io| io.fileno }


  while (num_to_read > 0)
    send_this_time = num_to_read > block_size ? block_size : num_to_read
    recv_result = IO.trysplice(recv_socket_fd,nil,wfd,nil,send_this_time,flags) 
    case recv_result
    when :EAGAIN
      readables, _, errored = IO.select([recv_socket], nil, [recv_socket], timeout)
      raise "recv fail" if !errored.empty?
    else
      bytes_in_buffer += recv_result
      read_so_far += recv_result
    end
    while (bytes_in_buffer > 0)
      send_result = IO.trysplice(rfd,nil,send_socket_fd,nil,bytes_in_buffer,flags)
      case send_result
      when :EAGAIN
        _, writeables, errored = IO.select(nil, [writable_socket], [writable_socket], timeout)
        raise "send fail" if !errored.empty?
      else
        bytes_in_buffer -= send_result
        num_to_read -= send_result
        sent_so_far += send_result
        yield send_result if block_given? 
      end
    end
  end
  sent_so_far
end
