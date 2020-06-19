#ifndef GIT_IPC_H
#define GIT_IPC_H

/*
 * "Simple IPC" implements a simple communication mechanism between one or
 * more (foreground) Git clients and an existing (background) "ipc-server".
 * It provides a communication foundation, but does not know about any
 * "application" built upon it.
 *
 * Communication occurs over named pipes on Windows and Unix Domain Sockets
 * on other platforms.  Rendezvous is via an application-specific pipe or
 * socket `path`.  (Platform-specific code will normalize this path.)
 *
 * Communication uses pkt-line format, but that detail is hidden from both
 * the client and server portions of the application.
 *
 * With Simple IPC:
 * [] A client (process) connects to an existing server (process).
 * [] The client sends a single command/request message to the server.
 * [] The server responds with a single response message.
 * [] Both sides close the pipe or socket.
 */

#if defined(GIT_WINDOWS_NATIVE) || !defined(NO_UNIX_SOCKETS)
#define SUPPORTS_SIMPLE_IPC
#endif

/* Return this from your `application_cb()` to shutdown the ipc-server. */
#define SIMPLE_IPC_QUIT -2

struct ipc_server_data;
struct ipc_server_reply_data;

typedef int (ipc_server_reply_cb)(struct ipc_server_reply_data *,
				  const char *response,
				  size_t response_len);

typedef int (ipc_server_application_cb)(void *application_data,
					const char *request,
					ipc_server_reply_cb *reply_cb,
					struct ipc_server_reply_data *reply_data);

enum IPC_ACTIVE_STATE {
	IPC_STATE__ACTIVE = 0,
	IPC_STATE__NOT_ACTIVE = 1,
	IPC_STATE__INVALID_PATH = 2,
};

/*
 * Inspect the filesystem to determine if a server is running on this
 * named pipe or socket (without actually sending a message) by testing
 * the availability and/or existence of the pipe or socket.
 */
enum IPC_ACTIVE_STATE ipc_is_active(const char *path);

/*
 * Used by the client to synchronously send a message to the server and
 * receive a response.
 *
 * Returns 0 when successful.
 *
 * Calls error() and returns non-zero otherwise.
 */
int ipc_client_send_command(const char *path, const char *message,
			    struct strbuf *answer);

/*
 * Synchronously run an `ipc-server` instance in the current process.  (This
 * is a thread pool running in the background to service client connections.)
 *
 * Returns 0 if the server ran successfully (server threads were started
 * and cleanly stopped).
 *
 * Calls error() and returns non-zero otherwise.
 *
 * When a client message is received, the application-specific
 * `application_cb` will be called (on a random thread) to handle the
 * message.  The callback will be given a `reply_cb` to use to send
 * return data to the client.  The `reply_cb` can be called multiple
 * times for chunking purposes.  Any reply is optional.
 *
 */
int ipc_server_run(const char *path, int nr_threads,
		   ipc_server_application_cb *application_cb,
		   void *application_data);

/*
 * Asynchronously starts an `ipc-server` instance in the current process.
 * A background thread pool is created to process client connections.
 *
 * Returns 0 and the address of the server instance if the server was
 * successfully started.
 */
int ipc_server_run_async(struct ipc_server_data **returned_server_data,
			 const char *path, int nr_threads,
			 ipc_server_application_cb *application_cb,
			 void *application_data);

/*
 * Asynchronously signal the threads in this `ipc-server` to stop.
 * This call will return immediately.
 */
int ipc_server_stop_async(struct ipc_server_data *server_data);

/*
 * Synchronously wait for the server to be signalled and all of the
 * server threads have been joined.
 *
 * Returns 0 if the server was cleanly stopped.
 */
int ipc_server_await(struct ipc_server_data *server_data);

void ipc_server_free(struct ipc_server_data *server_data);

#endif
