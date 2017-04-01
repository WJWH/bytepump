#include "ruby.h"
#include "ruby/io.h" //defines rb_cIO zodat je je eigen methods onder IO kan hangen
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/select.h>

VALUE FD_splice = Qnil;
VALUE FDS = Qnil;

#if ! HAVE_RB_IO_T
#  define rb_io_t OpenFile
#endif

#ifdef GetReadFile
#  define FPTR_TO_FD(fptr) (fileno(GetReadFile(fptr)))
#else
#  if !HAVE_RB_IO_T || (RUBY_VERSION_MAJOR == 1 && RUBY_VERSION_MINOR == 8)
#    define FPTR_TO_FD(fptr) fileno(fptr->f)
#  else
#    define FPTR_TO_FD(fptr) fptr->fd
#  endif
#endif

//gets the file descriptor out of the ruby IO object 
static int get_rb_fileno(VALUE io)
{
	rb_io_t *fptr; //
	GetOpenFile(io, fptr);
	return FPTR_TO_FD(fptr);
}

//returning zero means it timed out, returning 1 means data is available to be read or written
//returning -1 means select encountered an error
//eventually implement evading the gvl for this one (or just use one of the existing ones from thread.c?)
static int wait_for_fd(int fd, long timeout, int readsock){
    fd_set fds;
    struct timeval tv;
    int retval;
    //setup the fd set
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    //fill the timeout structure -> timeout seconds, no milliseconds
    tv.tv_sec = timeout;
    tv.tv_usec = 0;
    //do the actual select, different if you are wanting to write or wanting to read
    if (readsock){//wait for socket readable
        retval = select(fd+1, &fds, NULL, NULL, &tv);
    }
    else{//wait for socket writeable instead
        retval = select(fd+1, NULL, &fds, NULL, &tv);
    }
    return retval;
}

static VALUE rb_io_test_moveloop(VALUE read_socket, VALUE write_socket) {
    //extract the sockets from their ruby objects
    int read_sock_fd, write_sock_fd, result;
    long timeout = 10;//ten seconds for testing
    read_sock_fd = get_rb_fileno(read_socket);
    write_sock_fd = get_rb_fileno(write_socket);
    //whether a block was given doesn't change, so we might as well cache it 
    int block_given = rb_block_given_p();
    //the splice flags are always the same anyway
    unsigned int spliceopts = SPLICE_F_NONBLOCK | SPLICE_F_MORE | SPLICE_F_MOVE;
    //splice can't move data directly between data descriptors, it needs a kernel buffer in between to moderate
    //the pipe call makes such a buffer for us.
    int pipefd[2];
    result = pipe(pipefd);
    if (result < 0){
        return ID2SYM( rb_intern( "pipe_error" )); //
    }
    int bytesinpipe = 0; //int should be enogh as default pipe size is only 64 kb
    unsigned long long bytes_sent = 0;//64 bits should be enough for a while (famous last words)
    //now to do the copying
    //splice only returns 0 at eof
    while (result = splice(read_sock_fd, 0, pipefd[1], NULL, 65536, spliceopts)){
        if (result == -1){
            if(errno == EAGAIN){
                result = wait_for_fd(read_sock_fd, timeout, 1);
                if (result < 0) { 
                    close(pipefd[0]);
                    close(pipefd[1]);
                    return ID2SYM( rb_intern( "select_error" ));
                }
                else if (result == 0) {
                    //select timed out
                    close(pipefd[0]);
                    close(pipefd[1]);
                    return ID2SYM( rb_intern( "timeout_upstream" ));
                }
                else {
                    //we can continue reading now, nothing to see here.
                    //pipe should still be empty, so the read loop will be skipped and we
                    //go straight back to the splice from the read socket
                }
            }
            else {
                close(pipefd[0]);
                close(pipefd[1]);
                return ID2SYM( rb_intern( "splice_error" ));
            }
        }
        else{
            bytesinpipe += result;
        }
        //move data from the pipe to the output file
        while(bytesinpipe){ // > 0 is impliciet
            result = splice(pipefd[0], NULL, write_sock_fd, 0, 65536, spliceopts);
            if (result == -1){
                if(errno == EAGAIN){
                    result = wait_for_fd(write_sock_fd, timeout, 0);
                    if (result < 0) { 
                        //select returned an error
                        close(pipefd[0]);
                        close(pipefd[1]);
                        return ID2SYM( rb_intern( "select_error" ));
                    }
                    else if (result == 0) {
                        //the select call timed out
                        close(pipefd[0]);
                        close(pipefd[1]);
                        return ID2SYM( rb_intern( "timeout_downstream" ));
                    }
                    else {
                        //the select call returned positive nonzero, and since it was only watching one fd 
                        //that means we can continue writing now
                        }
                }
                else {
                    //another type of error happened that we can't recover from
                    close(pipefd[0]);
                    close(pipefd[1]);
                    return ID2SYM( rb_intern( "splice_error" ));
                }
            }
            else{//write succesful
                bytes_sent += result;
                bytesinpipe -= result;
                if(block_given)
                    rb_yield(INT2NUM(result));
            }
        } //end of writing while loop
    } //end of reading while loop
    
    close(pipefd[0]);
    close(pipefd[1]);
    return ULL2NUM(bytes_sent);
}


//setup the lib
void Init_bytepump(void)
{
	rb_define_method(rb_cIO, "splice_to", rb_io_spliceloop, 1);
    
}

