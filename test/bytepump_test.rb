require 'test_helper'
require 'bytepump'
require 'socket'
require 'io/nonblock'

class BytepumpTest < Minitest::Test
  def md5(filename)
    `md5sum #{filename}`.split[0]
  end

  def test_that_it_has_a_version_number
    refute_nil ::Bytepump::VERSION
  end

  def setup
    @input_file ||= 'test/testfile.bin'
    @output_file ||= 'test/output.bin'
    return if File.exist? @input_file # rubocop suggested this? :|
    f = File.open @input_file, 'w'
    f << Random.new.bytes(10 * 1024 * 1024)
    f.close
  end

  def teardown
    File.delete @output_file if File.exist? @output_file
  end

  def test_it_splices_between_files
    f1 = File.open @input_file
    f2 = File.open @output_file, 'w' # will overwrite any previous contents
    @running_total = 0
    bytes_sent = f1.splice_to(f2) { |b| @running_total += b }
    assert_equal f1.size, bytes_sent # the whole file must have been sent
    assert_equal md5(@input_file), md5(@output_file) # files must be equal
    assert_equal bytes_sent, @running_total # block reporting must be accurate
    f1.close
    f2.close
  end

  def receiving_server(filename, port)
    Thread.new do
      f = File.open filename, 'w' # will overwrite any previous contents
      ss = TCPServer.new port
      s = ss.accept
      s.nonblock = true
      s.splice_to(f, 1)
      s.close
      ss.close
      f.close
    end
  end

  def test_it_splices_from_file_to_socket
    t = receiving_server @output_file, 3001
    sleep 0.1 # wait for the server socket to start up
    f1 = File.open @input_file
    s = TCPSocket.new '127.0.0.1', 3001
    s.nonblock = true # if you forget this on big inputs it'll need a kill -9
    f1.splice_to(s, 3) # timeout of 3 sec
    s.close
    t.join # wait for thread to finish
    assert_equal md5(@input_file), md5(@output_file) # files must be equal
  end

  # spliced out no-op server thread to satisfy rubycop
  def start_server(port)
    Thread.new do
      ss = TCPServer.new port
      ss.accept
      ss.close
      sleep 3
    end
  end

  # when trying this test, make sure the testing file is big enough to not fit
  # in the socket buffer anymore on my system 10mb is enough
  def test_socket_downstream_splicing_times_out
    f1 = File.open @input_file
    t = start_server 3002 # open accepting socket in different thread
    sleep 0.1 # wait for the server socket to start up
    s = TCPSocket.new '127.0.0.1', 3002
    s.nonblock = true
    result = f1.splice_to(s, 0) # set timeout of 0 seconds
    t.kill
    assert_equal :timeout_downstream, result
  end

  def test_socket_upstream_splicing_times_out
    f = File.open @output_file, 'w' # will overwrite any previous contents
    t = start_server 3003 # open accepting socket in different thread
    sleep 0.1 # wait for the server socket to start up
    s = TCPSocket.new '127.0.0.1', 3003
    s.nonblock = true
    result = s.splice_to(f, 0) # set timeout of 0 seconds
    t.kill
    assert_equal :timeout_upstream, result
  end
end
