#include "cache.h"
#include "simple-ipc.h"
#include "strbuf.h"
#include "pkt-line.h"
#include "thread-utils.h"

#ifdef GIT_WINDOWS_NATIVE
static int initialize_pipe_name(const char *path, wchar_t *wpath, size_t alloc)
{
	int off = 0;
	struct strbuf realpath = STRBUF_INIT;

	// TODO Should these 2 errors cases also set `errno` ?
	// TODO Should this layer print error messages ?

	if (!strbuf_realpath(&realpath, path, 0))
		return error(_("could not normalize path '%s'"), path);

	off = swprintf(wpath, alloc, L"\\\\.\\pipe\\");
	if (xutftowcs(wpath + off, realpath.buf, alloc - off) < 0)
		return error(_("could not determine pipe path for '%s'"),
			     realpath.buf);

	// TODO Note that items within the NPFS don't have to follow
	// TODO Win32/NTFS pathname rules, so this munging may not
	// TODO be necessary.

	/* Handle drive prefix */
	if (wpath[off] && wpath[off + 1] == L':') {
		wpath[off + 1] = L'_';
		off += 2;
	}

	for (; wpath[off]; off++)
		if (wpath[off] == L'/')
			wpath[off] = L'\\';

	strbuf_release(&realpath);
	return 0;
}

// TODO revisit the naming of this.  It basically verifies that a named
// TODO pipe with this pathname exists.  It doesn't verify that *our*
// TODO daemon is listening on it.
//
// TODO Would this be clearer if it was:
// TOOD    return (WaitNamedPipeW() || GetLastError() == ERROR_SEM_TIMEOUT);
//
static enum IPC_ACTIVE_STATE is_active(wchar_t *pipe_path)
{
	if (WaitNamedPipeW(pipe_path, 1) ||
	    GetLastError() != ERROR_FILE_NOT_FOUND)
		return IPC_STATE__ACTIVE;
	else
		return IPC_STATE__NOT_ACTIVE;
}

enum IPC_ACTIVE_STATE ipc_is_active(const char *path)
{
	wchar_t pipe_path[MAX_PATH];

	// TODO Should this fail harder if they give us a bogus path ?
	// TODO As it is, a client with a bogus path could spin wait
	// TODO forever waiting for a server to start because it can't
	// TODO tell that from a valid path with no server.

	if (initialize_pipe_name(path, pipe_path, ARRAY_SIZE(pipe_path)) < 0)
		return IPC_STATE__INVALID_PATH;

	return is_active(pipe_path);
}

/*
 * Duplicate the given pipe handle and wrap it in a file descriptor so
 * that we can use pkt-line on it.
 */
static int dup_fd_from_pipe(const HANDLE pipe)
{
	HANDLE process = GetCurrentProcess();
	HANDLE handle;
	int fd;

	if (!DuplicateHandle(process, pipe, process, &handle, 0, FALSE,
			     DUPLICATE_SAME_ACCESS)) {
		errno = err_win_to_posix(GetLastError());
		return -1;
	}

	fd = _open_osfhandle((intptr_t)handle, O_RDWR|O_BINARY);
	if (fd < 0) {
		errno = err_win_to_posix(GetLastError());
		CloseHandle(handle);
		return -1;
	}

	return fd;
}

//////////////////////////////////////////////////////////////////

static const char *MAGIC_SERVER_REPLY_DATA = "T_Reply_T";
static const char *MAGIC_SERVER_THREAD_DATA = "T_Thread_T";
static const char *MAGIC_SERVER_DATA = "T_Server_T";

struct ipc_server_reply_data {
	const char *magic;
	int fd;
	struct ipc_server_thread_data *server_thread_data;
};

struct ipc_server_thread_data {
	const char *magic;
	struct ipc_server_thread_data *next_thread;
	struct ipc_server_data *server_data;
	int thread_nr;
	pthread_t pthread_id;
	HANDLE hPipe;
};

struct ipc_server_data {
	const char *magic;
	ipc_server_application_cb *application_cb;
	void *application_data;
	HANDLE hEventStopRequested;
	struct strbuf buf_path;
	wchar_t wpath[MAX_PATH];
	struct ipc_server_thread_data *thread_list;
};

enum connect_result {
	CR_CONNECTED = 0,
	CR_CONNECT_PENDING,
	CR_CONNECT_ERROR,
	CR_WAIT_ERROR,
	CR_SHUTDOWN,
};

static enum connect_result queue_overlapped_connect(
	struct ipc_server_thread_data *server_thread_data,
	OVERLAPPED *lpo)
{
	if (ConnectNamedPipe(server_thread_data->hPipe, lpo))
		goto failed;

	switch (GetLastError()) {
	case ERROR_IO_PENDING:
		return CR_CONNECT_PENDING;

	case ERROR_PIPE_CONNECTED:
		SetEvent(lpo->hEvent);
		return CR_CONNECTED;

	default:
		break;
	}

failed:
	error(_("ConnectNamedPipe failed for '%s' (%lu)"),
	      server_thread_data->server_data->buf_path.buf,
	      GetLastError());
	return CR_CONNECT_ERROR;
}

static enum connect_result wait_for_connection(
	struct ipc_server_thread_data *server_thread_data,
	OVERLAPPED *lpo)
{
	enum connect_result r;
	HANDLE waitHandles[2];
	DWORD dwWaitResult;

	r = queue_overlapped_connect(server_thread_data, lpo);
	if (r != CR_CONNECT_PENDING)
		return r;

	waitHandles[0] = server_thread_data->server_data->hEventStopRequested;
	waitHandles[1] = lpo->hEvent;

	dwWaitResult = WaitForMultipleObjects(2, waitHandles, FALSE, INFINITE);
	switch (dwWaitResult) {
	case WAIT_OBJECT_0 + 0:
		trace2_printf("ipc-server[%s]: received stop event",
			      server_thread_data->server_data->buf_path.buf);
		return CR_SHUTDOWN;

	case WAIT_OBJECT_0 + 1:
//		trace2_printf("ipc-server[%s]: received connection",
//			      server_thread_data->server_data->buf_path.buf);
		ResetEvent(lpo->hEvent);
		return CR_CONNECTED;

	default:
		return CR_WAIT_ERROR;
	}
}

static ipc_server_reply_cb do_io_reply;

static int do_io_reply(struct ipc_server_reply_data *reply_data,
		       const char *response, size_t response_len)
{
	if (reply_data->magic != MAGIC_SERVER_REPLY_DATA)
		BUG("reply_cb called with wrong instance data");

	return write_packetized_from_buf(response, response_len,
					 reply_data->fd, 0);
}

/*
 * Receive the request/command from the client and pass it to the
 * registered request-callback.  The request-callback will compose
 * a response and call our reply-callback to send it to the client.
 */
static int do_io(struct ipc_server_thread_data *server_thread_data)
{
	struct strbuf buf = STRBUF_INIT;
	struct ipc_server_reply_data reply_data;
	int ret = 0;

	reply_data.magic = MAGIC_SERVER_REPLY_DATA;
	reply_data.server_thread_data = server_thread_data;

	reply_data.fd = dup_fd_from_pipe(server_thread_data->hPipe);
	if (reply_data.fd < 0)
		return error(_("could not create fd from pipe for '%s'"),
			     server_thread_data->server_data->buf_path.buf);

	ret = read_packetized_to_strbuf(reply_data.fd, &buf,
					PACKET_READ_NEVER_DIE);
	if (ret >= 0) {
//		trace2_printf("simple-ipc: %s", buf.buf);

		ret = server_thread_data->server_data->application_cb(
			server_thread_data->server_data->application_data,
			buf.buf, do_io_reply, &reply_data);

		packet_flush_gently(reply_data.fd);

		FlushFileBuffers((HANDLE)_get_osfhandle((reply_data.fd)));
	}
	else {
		/*
		 * The client probably disconnected/shutdown before it
		 * could send a well-formed message.  Ignore it.
		 */
		trace2_printf("ipc-server[%s]: read_packetized failed",
			      server_thread_data->server_data->buf_path.buf);
	}

	strbuf_release(&buf);
	close(reply_data.fd);

	return ret;
}

/*
 * Handle IPC request and response with this connected client.  And reset
 * the pipe to prepare for the next client.
 */
static int use_connection(struct ipc_server_thread_data *server_thread_data)
{
	int ret;

	ret = do_io(server_thread_data);

	FlushFileBuffers(server_thread_data->hPipe);
	DisconnectNamedPipe(server_thread_data->hPipe);

	return ret;
}

static void *server_thread_proc(void *_server_thread_data)
{
	struct ipc_server_thread_data *server_thread_data = _server_thread_data;
	HANDLE hEventConnected = INVALID_HANDLE_VALUE;
	OVERLAPPED oConnect;
	enum connect_result cr;
	int ret;

	assert(server_thread_data->hPipe != INVALID_HANDLE_VALUE);

	trace2_thread_start("ipc-server");
	trace2_data_string("ipc-server", NULL, "pipe",
			   server_thread_data->server_data->buf_path.buf);

	hEventConnected = CreateEventW(NULL, TRUE, FALSE, NULL);

	memset(&oConnect, 0, sizeof(oConnect));
	oConnect.hEvent = hEventConnected;

	while (1) {
		cr = wait_for_connection(server_thread_data, &oConnect);

		switch (cr) {
		case CR_SHUTDOWN:
			goto finished;

		case CR_CONNECTED:
			ret = use_connection(server_thread_data);
			if (ret == SIMPLE_IPC_QUIT) {
				ipc_server_stop_async(
					server_thread_data->server_data);
				goto finished;
			}
			if (ret > 0) {
				/*
				 * Ignore (transient) IO errors with this
				 * client and reset for the next client.
				 */
			}
			break;

		case CR_CONNECT_PENDING:
			/* By construction, this should not happen. */
			BUG("ipc-server[%s]: unexpeced CR_CONNECT_PENDING",
			    server_thread_data->server_data->buf_path.buf);

		case CR_CONNECT_ERROR:
		case CR_WAIT_ERROR:
			/*
			 * TODO These are theoretical errors at this point.
			 * TODO Should this shutdown the server (and all the
			 * TODO other threads) or just reset this pipe instance?
			 */
			DisconnectNamedPipe(server_thread_data->hPipe);
			break;

		default:
			BUG("unandled case after wait_for_connection");
		}
	}

finished:
	CloseHandle(server_thread_data->hPipe);
	CloseHandle(hEventConnected);

	trace2_thread_exit();
	return NULL;
}

static HANDLE create_new_pipe(wchar_t *wpath, int is_first)
{
	HANDLE hPipe;
	DWORD dwOpenMode, dwPipeMode;
	LPSECURITY_ATTRIBUTES lpsa = NULL;

	dwOpenMode = PIPE_ACCESS_INBOUND | PIPE_ACCESS_OUTBOUND |
		FILE_FLAG_OVERLAPPED;

	dwPipeMode = PIPE_TYPE_MESSAGE | PIPE_READMODE_BYTE | PIPE_WAIT |
		PIPE_REJECT_REMOTE_CLIENTS;

	if (is_first) {
		dwOpenMode |= FILE_FLAG_FIRST_PIPE_INSTANCE;

		/* TODO consider setting security attributes. */
	}

	hPipe = CreateNamedPipeW(wpath, dwOpenMode, dwPipeMode,
				 PIPE_UNLIMITED_INSTANCES, 1024, 1024, 0, lpsa);

	return hPipe;
}

int ipc_server_run_async(struct ipc_server_data **returned_server_data,
			 const char *path, int nr_threads,
			 ipc_server_application_cb *application_cb,
			 void *application_data)
{
	struct ipc_server_data *server_data;
	wchar_t wpath[MAX_PATH];
	HANDLE hPipeFirst = INVALID_HANDLE_VALUE;
	int k;
	int ret = 0;

	*returned_server_data = NULL;

	ret = initialize_pipe_name(path, wpath, ARRAY_SIZE(wpath));
	if (ret < 0)
		return ret;

	hPipeFirst = create_new_pipe(wpath, 1);
	if (hPipeFirst == INVALID_HANDLE_VALUE)
		return error(_("server already running on '%s'"), path);

	server_data = xcalloc(1, sizeof(*server_data));
	server_data->magic = MAGIC_SERVER_DATA;
	server_data->application_cb = application_cb;
	server_data->application_data = application_data;
	server_data->hEventStopRequested = CreateEvent(NULL, TRUE, FALSE, NULL);
	strbuf_init(&server_data->buf_path, 0);
	strbuf_addstr(&server_data->buf_path, path);
	wcscpy(server_data->wpath, wpath);

	if (nr_threads < 1)
		nr_threads = 1;

	for (k = 0; k < nr_threads; k++) {
		struct ipc_server_thread_data *std;

		std = xcalloc(1, sizeof(*std));
		std->magic = MAGIC_SERVER_THREAD_DATA;
		std->server_data = server_data;
		std->thread_nr = k;
		std->hPipe = INVALID_HANDLE_VALUE;

		std->hPipe = (k == 0)
			? hPipeFirst
			: create_new_pipe(server_data->wpath, 0);

		if (std->hPipe == INVALID_HANDLE_VALUE) {
			/*
			 * If we've reached a pipe instance limit for
			 * this path, just use fewer threads.
			 */
			free(std);
			break;
		}

		if (pthread_create(&std->pthread_id, NULL,
				   server_thread_proc, std)) {
			/*
			 * Likewise, if we're out of threads, just use
			 * fewer threads than requested.
			 */
			CloseHandle(std->hPipe);
			free(std);
			break;
		}

		std->next_thread = server_data->thread_list;
		server_data->thread_list = std;
	}

	*returned_server_data = server_data;
	return 0;
}

int ipc_server_stop_async(struct ipc_server_data *server_data)
{
	if (!server_data)
		return 0;

	trace2_printf("EEE: Stopping '%s'", server_data->buf_path.buf);

	/*
	 * Gently tell all of the ipc_server threads to shutdown.
	 * This will be seen the next time they are idle (and waiting
	 * for a connection).
	 *
	 * We DO NOT attempt to force them to drop an active connection.
	 *
	 * TODO Should we have a force-now option?
	 */
	SetEvent(server_data->hEventStopRequested);
	return 0;
}

int ipc_server_await(struct ipc_server_data *server_data)
{
	DWORD dwWaitResult;

	if (!server_data)
		return 0;

	dwWaitResult = WaitForSingleObject(server_data->hEventStopRequested, INFINITE);
	if (dwWaitResult != WAIT_OBJECT_0)
		return error(_("wait for hEvent failed for '%s'"),
			     server_data->buf_path.buf);

	while (server_data->thread_list) {
		struct ipc_server_thread_data *std = server_data->thread_list;

		pthread_join(std->pthread_id, NULL);

		server_data->thread_list = std->next_thread;
		free(std);
	}

	return 0;
}

int ipc_server_run(const char *path, int nr_threads,
		   ipc_server_application_cb *application_cb,
		   void *application_data)
{
	struct ipc_server_data *server_data = NULL;
	int ret;

	ret = ipc_server_run_async(&server_data, path, nr_threads,
				   application_cb, application_data);
	if (ret)
		return ret;

	ret = ipc_server_await(server_data);

	ipc_server_free(server_data);

	return ret;
}

void ipc_server_free(struct ipc_server_data *server_data)
{
	// TODO Free server_data
}

//////////////////////////////////////////////////////////////////

static int connect_to_server(const char *path, const wchar_t *wpath,
			     DWORD timeout_ms, HANDLE *phPipe)
{
	DWORD t_start_ms, t_waited_ms;

	while (1) {
		*phPipe  = CreateFileW(wpath, GENERIC_READ | GENERIC_WRITE,
				       0, NULL, OPEN_EXISTING, 0, NULL);
		if (*phPipe != INVALID_HANDLE_VALUE)
			return 0;

		if (GetLastError() != ERROR_PIPE_BUSY) {
			/*
			 * We expect ERROR_FILE_NOT_FOUND when the server is not
			 * running, but other errors are possible here.
			 */
			return error(_("could not open pipe '%s' (gle %ld)"),
				     path, GetLastError());
		}

		t_start_ms = (DWORD)(getnanotime() / 1000000);

		if (!WaitNamedPipeW(wpath, timeout_ms)) {
			if (GetLastError() == ERROR_SEM_TIMEOUT)
				return error(_("pipe is busy '%s'"), path);

			return error(_("could not open '%s' (gle %ld)"),
				     path, GetLastError());
		}

		/*
		 * A pipe server instance became available.  Race other client
		 * processes to connect to it.
		 *
		 * But first decrement our overall timeout so that we don't
		 * starve if we keep losing the race.  But also guard against
		 * special NPMWAIT_ values (0 and -1).
		 */
		t_waited_ms = (DWORD)(getnanotime() / 1000000) - t_start_ms;

		timeout_ms -= t_waited_ms;
		if (timeout_ms < 1)
			timeout_ms = 1;
	}
}

/*
 * The default connection timeout for Windows clients.
 *
 * This is not currently part of the ipc_ API (nor the config settings)
 * because of differences between Windows and other platforms.
 *
 * This value was chosen at random.
 */
#define WINDOWS_CONNECTION_TIMEOUT_MS (30000)

int ipc_client_send_command(const char *path, const char *message,
			    struct strbuf *answer)
{
	wchar_t wpath[MAX_PATH];
	HANDLE hPipe = INVALID_HANDLE_VALUE;
	DWORD mode = PIPE_READMODE_BYTE;
	int fd = -1;

	strbuf_setlen(answer, 0);

	if (initialize_pipe_name(path, wpath, ARRAY_SIZE(wpath)) < 0)
		return -1;

	if (connect_to_server(path, wpath, WINDOWS_CONNECTION_TIMEOUT_MS,
			      &hPipe))
		return -1;

	if (!SetNamedPipeHandleState(hPipe, &mode, NULL, NULL)) {
		CloseHandle(hPipe);
		return error(_("could not switch pipe to byte mode '%s'"),
			     path);
	}

	fd = _open_osfhandle((intptr_t)hPipe, O_RDWR|O_BINARY);
	if (fd < 0) {
		CloseHandle(hPipe);
		return error(_("could not create fd for pipe handle '%s'"),
			     path);
	}

	hPipe = INVALID_HANDLE_VALUE; /* fd owns it now */

	if (write_packetized_from_buf(message, strlen(message), fd, 1) < 0) {
		close(fd);
		return error(_("could not send IPC to '%s'"), path);
	}

	FlushFileBuffers((HANDLE)_get_osfhandle(fd));

	if (read_packetized_to_strbuf(fd, answer, PACKET_READ_NEVER_DIE) < 0) {
		close(fd);
		return error(_("could not read IPC response on '%s'"), path);
	}

	close(fd);
	return 0;
}
#elif !defined(NO_UNIX_SOCKETS)
#include "unix-socket.h"
#include "sigchain.h"

static int is_active(const char *path)
{
	struct stat st;

	// TODO Can't UDS exist on disk without an active listener ??
	// TODO So doesn't this just test that the server had in the
	// TODO past been active??

	return !lstat(path, &st) && (st.st_mode & S_IFMT) == S_IFSOCK;
}

int ipc_is_active(const char *path)
{
	return is_active(path);
}

static void set_socket_blocking_flag(int fd, int make_nonblocking)
{
	int flags;

	flags = fcntl(fd, F_GETFL, NULL);

	if (flags < 0)
		die(_("fcntl failed"));

	if (make_nonblocking)
		flags |= O_NONBLOCK;
	else
		flags &= ~O_NONBLOCK;

	if (fcntl(fd, F_SETFL, flags) < 0)
		die(_("fcntl failed"));
}

static int reply(void *reply_data, const char *response, size_t len)
{
	int fd = *(int *)reply_data;

	return write_packetized_from_buf(response, len, fd, 0);
}

/* in ms */
#define LISTEN_TIMEOUT 50000
#define RESPONSE_TIMEOUT 1000

static struct string_list listener_paths = STRING_LIST_INIT_DUP;
static int atexit_registered;

static void unlink_listener_path(void)
{
	int i;

	for (i = 0; i < listener_paths.nr; i++)
		unlink(listener_paths.items[i].string);

	string_list_clear(&listener_paths, 0);
}

int ipc_listen_for_commands(struct ipc_command_listener *listener)
{
	int ret = 0, fd;

	if (is_active(listener->path))
		return error(_("server already running at %s"), listener->path);

	fd = unix_stream_listen(listener->path);
	if (fd < 0)
		return error_errno(_("could not set up socket for %s"),
				   listener->path);

	if (!atexit_registered) {
		atexit(unlink_listener_path);
		atexit_registered = 1;
	}
	string_list_append(&listener_paths, listener->path);

	trace2_region_enter("simple-ipc", "listen", the_repository);
	listener->active = 1;
	while (listener->active) {
		struct pollfd pollfd;
		int result, client_fd;
		struct strbuf buf = STRBUF_INIT;

		/* Wait for a request */
		pollfd.fd = fd;
		pollfd.events = POLLIN;
		result = poll(&pollfd, 1, LISTEN_TIMEOUT);
		if (result < 0) {
			if (errno == EINTR)
				/*
				 * This can lead to an overlong keepalive,
				 * but that is better than a premature exit.
				 */
				continue;
			trace2_region_leave("simple-ipc", "listen", the_repository);
			return error_errno(_("poll() failed"));
		} else if (result == 0)
			/* timeout */
			continue;

		client_fd = accept(fd, NULL, NULL);
		if (client_fd < 0)
			/*
			 * An error here is unlikely -- it probably
			 * indicates that the connecting process has
			 * already dropped the connection.
			 */
			continue;

		/*
		 * Our connection to the client is blocking since a client
		 * can always be killed by SIGINT or similar.
		 */
		set_socket_blocking_flag(client_fd, 0);

		strbuf_reset(&buf);
		result = read_packetized_to_strbuf(client_fd, &buf,
						   PACKET_READ_NEVER_DIE);

		if (result > 0) {
			/* ensure string termination */
			ret = listener->handle_client(listener, buf.buf, reply,
						      &client_fd);
			packet_flush_gently(client_fd);
			if (ret == SIMPLE_IPC_QUIT) {
				listener->active = 0;
				close(client_fd);
				strbuf_release(&buf);
				break;
			}
		} else {
			/*
			 * No command from client.  Probably it's just a
			 * liveness check or client error.  Just close up.
			 */
		}
		close(client_fd);
	}

	close(fd);
	trace2_region_leave("simple-ipc", "listen", the_repository);
	return ret == SIMPLE_IPC_QUIT ? 0 : ret;
}

int ipc_send_command(const char *path, const char *message,
		     struct strbuf *answer)
{
	int fd = unix_stream_connect(path);
	int ret = 0;

	sigchain_push(SIGPIPE, SIG_IGN);
	if (fd < 0 ||
	    write_packetized_from_buf(message, strlen(message), fd, 1) < 0)
		ret = -1;
	else if (answer) {
		if (read_packetized_to_strbuf(fd, answer,
					      PACKET_READ_NEVER_DIE) < 0)
			ret = error_errno(_("could not read packet from '%s'"),
					  path);
	}

	if (fd >= 0)
		close(fd);
	sigchain_pop(SIGPIPE);
	return ret;
}
#endif
