require 'mkmf'

extension_name = "bytepump"

#paar haves?
have_header('fcntl.h') #voor splice
have_header('stdio.h') #voor fprint


create_makefile('bytepump')