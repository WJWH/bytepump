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
    unless File.exist? 'test/testfile.bin' 
      f = File.open 'test/testfile.bin','w'
      f << Random.new.bytes(10 * 1024 * 1024)
      f.close
    end
  end
  
  def teardown
    File.delete 'test/output.bin' if File.exist? 'test/output.bin'
  end
  
  def test_it_splices_between_files
    fn1 = 'test/testfile.bin'
    f1 = File.open fn1
    fn2 = 'test/output.bin'
    f2 = File.open fn2,'w' #will overwrite any previous contents
    @running_total = 0
    bytes_sent = f1.splice_to(f2) {|b| @running_total += b}
    assert_equal f1.size, bytes_sent #the whole file must have been sent
    assert_equal md5(fn1), md5(fn2) #files must be equal
    assert_equal bytes_sent, @running_total #the block reporting must be accurate
    f1.close
    f2.close
  end
  
  def test_it_splices_from_file_to_socket
    fn2 = 'test/output.bin'
    t = Thread.new do
      f2 = File.open fn2,'w' #will overwrite any previous contents 
      ss = TCPServer.new 3001
      s = ss.accept
      IO.copy_stream(s,f2) #assuming the copy_stream method is without bugs, of course
      s.close
      ss.close
      f2.close
    end
    sleep 0.1 #wait for the server socket to start up
    s2 = TCPSocket.new '127.0.0.1',3001
    #puts "socket opened"
    fn1 = 'test/testfile.bin'
    f1 = File.open fn1
    s2.nonblock = true # if you forget this with big inputs it'll require a kill -9
    f1.splice_to(s2,5)#timeout of 5 sec
    s2.close
    f1.close
    sleep 0.1 #give thread some time to finish 
    t.kill
    assert_equal md5(fn1), md5(fn2) #files must be equal
  end
  
  #when trying this test, make sure the testing file is big enough to not fit in the socket buffer anymore
  #on my system 10mb is enough
  def test_socket_downstream_splicing_times_out
    fn1 = 'test/testfile.bin'
    f1 = File.open fn1
    #open accepting socket
    t = Thread.new do
      ss = TCPServer.new 3002
      s = ss.accept
      ss.close
      sleep 3
    end
    sleep 0.1 #wait for the server socket to start up
    s = TCPSocket.new '127.0.0.1',3002
    s.nonblock = true
    result = f1.splice_to(s,0) #set timeout of 0 seconds
    t.kill
    assert_equal :timeout_downstream, result
  end
  
  def test_socket_upstream_splicing_times_out
    fn = 'test/output.bin'
    f = File.open fn,'w' #will overwrite any previous contents
    #open accepting socket
    t = Thread.new do
      ss = TCPServer.new 3003
      s = ss.accept
      ss.close
      sleep 3
    end
    sleep 0.1 #wait for the server socket to start up
    s = TCPSocket.new '127.0.0.1',3003
    s.nonblock = true
    result = s.splice_to(f,0) #set timeout of 0 seconds
    t.kill
    assert_equal :timeout_upstream, result
  end
end
  
  
  
  
  