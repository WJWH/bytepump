#include "ruby.h"
#include "ruby/io.h" //defines rb_cIO zodat je je eigen methods onder IO kan hangen
#include "ruby/thread.h" //defines the gvl evasion functions
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <sys/select.h>

//we always use the same flags for the splice() call anyway
unsigned int spliceopts = SPLICE_F_NONBLOCK | SPLICE_F_MORE | SPLICE_F_MOVE;

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
//define 
typedef void * (*my_blocking_fn_t)(void*);
#  define WITHOUT_GVL(fn,a) \
rb_thread_call_without_gvl((my_blocking_fn_t)(fn),(a),RUBY_UBF_IO,0)

struct select_args {
   int fd;
   long timeout;
   int readsock;
};

//gets the file descriptor out of the ruby IO object 
static int get_rb_fileno(VALUE io)
{
	rb_io_t *fptr; //
	GetOpenFile(io, fptr);
	return FPTR_TO_FD(fptr);
}

//all real waiting is done outside the GVL 
static void* select_no_gvl(void *data){
    fd_set fds;
    struct timeval tv;
    int rv;
    struct select_args *args = data;
    //setup the fd set
    int fd = args->fd;
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    //fill the timeout structure -> timeout seconds, no milliseconds
    tv.tv_sec = args->timeout;
    tv.tv_usec = 0;
    //
    if(args->readsock){
        rv = select(fd+1, &fds, NULL, NULL, &tv);
    }
    else{
        rv = select(fd+1, NULL, &fds, NULL, &tv);
    }
    return (VALUE)rv;
}

//returning zero means it timed out, returning 1 means data is available to be read or written
//returning -1 means select encountered an error
//eventually implement evading the gvl for this one (or just use one of the existing ones from thread.c?)
static int wait_for_fd(int fd, long timeout, int readsock){
    struct select_args args = {fd,timeout,readsock}; 
    int result;
    result = (int)rb_thread_call_without_gvl(select_no_gvl,&args,RUBY_UBF_IO,0);
    return result;
}


//static VALUE rb_io_spliceloop(VALUE read_socket, VALUE write_socket, VALUE timeout_val) {
static VALUE rb_io_spliceloop(int argc, VALUE *argv, VALUE read_socket) {
    VALUE retval, write_socket, timeout_val; 
    int pipefd[2], read_sock_fd, write_sock_fd, result, block_given, bytesinpipe = 0;
    long timeout;
    unsigned long long bytes_sent = 0;//64 bits should be enough for a while (famous last words)
    //convert args
    rb_scan_args(argc, argv, "11", &write_socket, &timeout_val);
    timeout = NIL_P(timeout_val) ? 60 : NUM2LONG(timeout_val);//if none given, use 60, else the value given
    //extract the sockets from their ruby objects
    read_sock_fd = get_rb_fileno(read_socket);
    write_sock_fd = get_rb_fileno(write_socket);
    //whether a block was given doesn't change, so we might as well cache it 
    block_given = rb_block_given_p();
    //splice can't move data directly between data descriptors, it needs a kernel buffer in between 
    //to moderate. The pipe call makes such a buffer for us.
    result = pipe(pipefd);
    if (result < 0){
        retval = ID2SYM( rb_intern( "pipe_error" )); //this should VERY rarely happen, but CHECK EVERYTHING
        goto end;
    }
    //now to do the copying
    //splice only returns 0 at eof
    while (result = splice(read_sock_fd, 0, pipefd[1], NULL, 65536, spliceopts)){
        if (result == -1){
            if(errno == EAGAIN){
                result = wait_for_fd(read_sock_fd, timeout, 1);
                if (result < 0) { //some error in select() happened
                    retval = ID2SYM( rb_intern( "select_error" ));
                    goto closepipe;
                }
                else if (result == 0) {//select timed out
                    retval = ID2SYM( rb_intern( "timeout_upstream" ));
                    goto closepipe;
                }
                else {//we can continue reading now, nothing to see here.
                    //pipe should still be empty, so the read loop will be skipped and we
                    //go straight back to the splice from the read socket
                }
            }
            else { //another type of error happened that we can't recover from
                retval = ID2SYM( rb_intern( "splice_error" ));
                goto closepipe;
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
                    if (result < 0) { //select returned an error
                        retval = ID2SYM( rb_intern( "select_error" ));
                        goto closepipe;
                    }
                    else if (result == 0) { //the select call timed out
                        retval = ID2SYM( rb_intern( "timeout_downstream" ));
                        goto closepipe;
                    }
                    else {//the select call returned positive nonzero, and since it 
                        // was only watching one fd that means we can continue writing now
                    }
                }
                else {//another type of error happened that we can't recover from
                    retval = ID2SYM( rb_intern( "splice_error" ));
                    goto closepipe;
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
    retval = ULL2NUM(bytes_sent);
    //some labels to jump to for error handling
    closepipe: //don't leak file descriptors for the generated pipes
    close(pipefd[0]);
    close(pipefd[1]);
    end: 
    return retval;
}


//setup the lib
void Init_bytepump(void)
{
	rb_define_method(rb_cIO, "splice_to", rb_io_spliceloop, -1);
    
}
