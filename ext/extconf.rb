require 'mkmf'

extension_name = 'bytepump'

# paar haves?
have_header('fcntl.h') # voor splice
have_header('stdio.h') # voor fprint

# The destination
dir_config(extension_name)

create_makefile('bytepump/bytepump')
