require 'test_helper'
require 'bytepump'
require 'socket'
require 'io/nonblock'

class BytepumpTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Bytepump::VERSION
  end

  def setup
  end
  
  def teardown
  end
  
  def test_it_splices_between_files
    
    assert true
  end
end
