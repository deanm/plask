// Plask.
// (c) Dean McNamee <dean@gmail.com>, 2010.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.

// This file is a bit tricky, for the following main reasons.
//
// - We run nib-less, so we have more control of startup and can run the main
//   loop ourselves.  This also allows our executable to be a bit more
//   contained and not require nibs in the bundle.
// 
// - We must integrate the Cocoa event loop with Node's event loop (libuv).
//   This requires a bit of care and the general approach follows below.
//
// The CFRunLoop (and Cocoa's run loop) is needed for UI messages, and needs
// to be run on the main thread.  We always want everything to run on the main
// thread, all JavaScript, UI, etc.  It would be best if we could have a
// completely single threaded approach to combine the two runloops.  However,
// CFRunLoop is mach-port based, and can't wait on a mixture of both mach ports
// and file descriptors.  The way CFSocket is implemented on a CFRunLoop uses a
// helper process and select() to proxy over a mach message to wake up the
// CFRunLoop.  Our approach is similar but managed manually.  In theory it
// is possible to wrap the kqueue in a CFFileDescriptor or CFSocket, and then
// this would be handled within the run-loop.  However, a few attempts at this
// had some unreliable results, and it is clearer to handled the threading
// ourselves then try to understand the implementation details of the internal
// helper process of CFRunLoop().  This also allows us to send the NSEvent
// required to wake up the loop directly from the helper thread, which should
// be safe since postEvent can be called from "subthreads".
//
// There is one additional complication in terms of integrating with libuv.
// We can select() on the kqueue for notifications, but we also need to make
// sure that all pending changes (additions, removals, etc) from within libuv
// have been committed to the kqueue.  Normally this happens during the uv loop
// right before blocking on the kqueue.  The run through the loop can cause
// timers to fire and other callbacks, which can create more new pending events
// to be updated.  Instead of trying to track if there are pending events and
// seeing if we need to run through the loop to update the kqueue, we hook into
// libuv's kevent call.  This allows us to see when changes are being made and
// when it's about to block.  When it goes for a blocking kevent() call, we
// make sure any pending changes are committed and then pump the Cocoa event
// loop while our helper thread select()s on the kqueue to see if there is
// anything ready.  If the kqueue wakes before the Cocoa loop, we send a
// synthentic event into the Cocoa loop to wake up the main thread, and we will
// then again call kevent() and return back into libuv.  This effectively means
// we've replaced libuv's core kevent() blocking call with a call to the Cocoa
// eventloop which will be woken up also if there is any activity on the
// kqueue, allowing us to block on the set of both Cocoa and libuv events.

#import <Cocoa/Cocoa.h>

// For kevent.
#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

// For select.
#include <sys/select.h>

#import "plaskAppDelegate.h"

#include "plask_bindings.h"

#include "v8.h"
#include "node.h"
#include "uv.h"

#include "v8_typed_array.h"

#define EVENTLOOP_DEBUG 0

#define EVENTLOOP_BYPASS_CUSTOM 0

#if EVENTLOOP_DEBUG
#define EVENTLOOP_DEBUG_C(x) x
#else
#define EVENTLOOP_DEBUG_C(x) do { } while(0)
#endif

static bool g_should_quit = false;
static int g_kqueue_fd = 0;
static int g_main_thread_pipe_fd = 0;
static int g_kqueue_thread_pipe_fd = 0;

// We're running nibless, so we don't have the typical MainMenu.nib.  This code
// sets up the "Apple Menu", the menu in the menu bar with your application
// title, next to the actual apple logo menu.  It is a bit of a mess to create
// it programmatically.  For example, see:
//    http://lapcatsoftware.com/blog/2007/06/17/
static void InitMenuBar() {
  // Our NSApplication is created with a nil mainMenu.
  [NSApp setMainMenu:[[NSMenu alloc] init]];

  NSMenu* menu = [[NSMenu alloc] initWithTitle:@""];

  [menu addItemWithTitle:@"About Plask"
        action:@selector(orderFrontStandardAboutPanel:)
        keyEquivalent:@""];

  [menu addItem:[NSMenuItem separatorItem]];

  [menu addItemWithTitle:@"Hide Plask"
        action:@selector(hide:)
        keyEquivalent:@"h"];

  [menu addItemWithTitle:@"Hide Others"
        action:@selector(hideOtherApplications:)
        keyEquivalent:@"h"];

  [menu addItemWithTitle:@"Show All"
        action:@selector(unhideAllApplications:)
        keyEquivalent:@""];

  [menu addItem:[NSMenuItem separatorItem]];

  [menu addItemWithTitle:@"Quit Plask"
        action:@selector(terminate:)
        keyEquivalent:@"q"];

  // The actual "Apple Menu" is the first sub-menu of the mainMenu menu.
  NSMenuItem* container_item = [[NSMenuItem alloc] initWithTitle:@""
                                                   action: nil
                                                   keyEquivalent:@""];
  [container_item setSubmenu:menu];
  [[NSApp mainMenu] addItem:container_item];
  // Call the undocumented setAppleMenu to make the menu the "Apple Menu".
  [NSApp setAppleMenu:menu];
  [container_item release];
  [menu release];
}

#if EVENTLOOP_DEBUG
void dump_kevent(const struct kevent* k) {
  const char* f = NULL;
  switch (k->filter) {
    case EVFILT_READ: f = "EVFILT_READ"; break;
    case EVFILT_WRITE: f = "EVFILT_WRITE"; break;
    case EVFILT_AIO: f = "EVFILT_AIO"; break;
    case EVFILT_VNODE: f = "EVFILT_VNODE"; break;
    case EVFILT_PROC: f = "EVFILT_PROC"; break;
    case EVFILT_SIGNAL: f = "EVFILT_SIGNAL"; break;
    case EVFILT_TIMER: f = "EVFILT_TIMER"; break;
    case EVFILT_MACHPORT: f = "EVFILT_MACHPORT"; break;
    case EVFILT_FS: f = "EVFILT_FS"; break;
    case EVFILT_USER: f = "EVFILT_USER"; break;
    case EVFILT_VM: f = "EVFILT_VM"; break;
  }
  printf("%d  %s (%d) %d %d\n",
      k->ident,
      f, k->filter,
      k->flags,
      k->fflags);
}
#endif

void kqueue_checker_thread(void* arg) {
  bool check_kqueue = false;

  NSAutoreleasePool* pool = [NSAutoreleasePool new];  // To avoid the warning.
  NSEvent* e = [NSEvent otherEventWithType:NSApplicationDefined
                                      location:NSMakePoint(0, 0)
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:8  // Arbitrary
                                         data1:0
                                         data2:0];

  while (true) {
    int nfds = g_kqueue_thread_pipe_fd + 1;
    fd_set fds;
    FD_ZERO(&fds);
    FD_SET(g_kqueue_thread_pipe_fd, &fds);
    if (check_kqueue) {
      FD_SET(g_kqueue_fd, &fds);
      if (g_kqueue_fd + 1 > nfds) nfds = g_kqueue_fd + 1;
    }

    EVENTLOOP_DEBUG_C((printf("Calling select: %d\n", check_kqueue)));
    int res = select(nfds, &fds, NULL, NULL, NULL);
    if (res <= 0) abort();  // TODO(deanm): Handle signals, etc.

    if (FD_ISSET(g_kqueue_fd, &fds)) {
      EVENTLOOP_DEBUG_C((printf("postEvent\n")));
      [NSApp postEvent:e atStart:YES];
      check_kqueue = false;
    }

    if (FD_ISSET(g_kqueue_thread_pipe_fd, &fds)) {
      char msg;
      ssize_t amt = read(g_kqueue_thread_pipe_fd, &msg, 1);
      if (amt != 1) abort();  // TODO(deanm): Handle errors.
      if (msg == 'q') {  // quit.
        EVENTLOOP_DEBUG_C((printf("quitting kqueue helper\n")));
        break;
      }
      check_kqueue = msg == '~';  // ~ - start, ! - stop.
    }
  }

  [pool drain];
}

int
kevent_hook(int kq, const struct kevent *changelist, int nchanges,
            struct kevent *eventlist, int nevents,
            const struct timespec *timeout) {
  int res;

  EVENTLOOP_DEBUG_C((printf("KQUEUE--- fd: %d changes: %d\n", kq, nchanges)));

#if EVENTLOOP_DEBUG
  for (int i = 0; i < nchanges; ++i) {
    dump_kevent(&changelist[i]);
  }
#endif

#if EVENTLOOP_BYPASS_CUSTOM
  int res = kevent(kq, changelist, nchanges, eventlist, nevents, timeout);
  printf("---> results: %d\n", res);
  for (int i = 0; i < res; ++i) {
    dump_kevent(&eventlist[i]);
  }
  return res;
#endif

  if (eventlist == NULL)  // Just updating the state.
    return kevent(kq, changelist, nchanges, eventlist, nevents, timeout);

  struct timespec zerotimeout;
  memset(&zerotimeout, 0, sizeof(zerotimeout));

  // Going for a poll.  A bit less optimial but we break it into two system
  // calls to make sure that the kqueue state is up to date.  We might as well
  // also peek since we basically get it for free w/ the same call.
  EVENTLOOP_DEBUG_C((printf("-- Updating kqueue state and peek\n")));
  res = kevent(kq, changelist, nchanges, eventlist, nevents, &zerotimeout);
  if (res != 0) return res;

  /*
  printf("kevent() blocking\n");
  res = kevent(kq, NULL, 0, eventlist, nevents, timeout);
  if (res != 0) return res;
  return res;
  */

  /*
  printf("Going for it...\n");
  res = kevent(kq, changelist, nchanges, eventlist, nevents, timeout);
  printf("<- %d\n", res);
  return res;
  */

  double ts = 9999;  // Timeout in seconds.  Default to some "future".
  if (timeout != NULL)
    ts = timeout->tv_sec + (timeout->tv_nsec / 1000000000.0);

  // NOTE(deanm): We only ever make a single pass, because we need to make
  // sure that any user code (which could update timers, etc) is reflected
  // and we have a proper timeout value.  Since user code can run in response
  // to [NSApp sendEvent] (mouse movement, keypress, etc, etc), we wind down
  // and go back through the uv loop again to make sure to update everything.

  EVENTLOOP_DEBUG_C((printf("-> Running NSApp iteration: timeout %f\n", ts)));

  // Have the helper thread start select()ing on the kqueue.
  write(g_main_thread_pipe_fd, "~", 1);

  // Run the event loop (blocking on the mach port for window messages).
  NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
                          untilDate:[NSDate dateWithTimeIntervalSinceNow:ts]
                          inMode:NSDefaultRunLoopMode // kCFRunLoopDefaultMode
                          dequeue:YES];

  // Stop the helper thread if it hasn't already woken up (in which case it
  // would have already stopped itself).
  write(g_main_thread_pipe_fd, "!", 1);

  EVENTLOOP_DEBUG_C((printf("<- Finished NSApp iteration\n")));

  if (event != nil) {  // event is nil on a timeout.
    EVENTLOOP_DEBUG_C((NSLog(@"Event: %@\n", event)));

    // A custom event to terminate, see applicationShouldTerminate.
    if ([event type] == NSApplicationDefined && [event subtype] == 37) {
      EVENTLOOP_DEBUG_C((printf("* Application Terminate event.\n")));
      g_should_quit = true;
      write(g_main_thread_pipe_fd, "q", 1);
      return 0;  // See the notes about the dummy timer.
    } else if ([event type] == NSApplicationDefined && [event subtype] == 8) {
      // A wakeup after the kqueue callback.
      EVENTLOOP_DEBUG_C((printf("* Wakeup event.\n")));
    } else {
      [event retain];
      [NSApp sendEvent:event];
      [event release];
    }
  }

  // Do the actual kqueue call now (ignore the timeout, don't block).
  return kevent(kq, NULL, 0, eventlist, nevents, &zerotimeout);
}

static void dummy_cb(uv_timer_t* handle, int status) {
  EVENTLOOP_DEBUG_C((printf("dummy timer actually fired, interesting...\n")));
}

static void RunMainLoop() {
  // TODO Probably don't need to start this each time.
  // Avoids failing on test/simple/test-eio-race3.js though
  // ev_idle_start(EV_DEFAULT_UC_ &eio_poller);

  int pipefds[2];
  if (pipe(pipefds) != 0) abort();

  g_kqueue_thread_pipe_fd = pipefds[0];
  g_main_thread_pipe_fd = pipefds[1];

  uv_loop_t* uvloop = uv_default_loop();
  uvloop->keventfunc = (void*)&kevent_hook;

  g_kqueue_fd = uv_backend_fd(uvloop);

  uv_thread_t checker;
  uv_thread_create(&checker, &kqueue_checker_thread, NULL);

  // There is an assert if the kqueue returns 0 but there was a timeout of
  // -1 (infinite).  In order to avoid the logic of ever having no timeout
  // set a dummy timer just to enforce some large timeout and avoid the assert.
  // NOTE(deanm): We seem to hit some internal limit (libuv?) at 1410064 secs,
  // (16 days), so keep it under to be safe.  Doesn't matter if it fires anyway.
  static const int64_t kDummyTimerMs = 999999999L;  // ~11.5 days.
  uv_timer_t dummy_timer;
  uv_timer_init(uvloop, &dummy_timer);
  uv_timer_start(&dummy_timer, &dummy_cb, kDummyTimerMs, kDummyTimerMs);

  EVENTLOOP_DEBUG_C((printf("Kqueue fd: %d\n", uv_backend_fd(uvloop))));

  // Our dummy timer is always 1 active handle.
  while (!g_should_quit && uvloop->active_handles > 1) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    EVENTLOOP_DEBUG_C((printf("-> uv_run_once\n")));
    uv_run(uvloop, UV_RUN_ONCE);  // uv_run_once(uvloop);
    EVENTLOOP_DEBUG_C((printf("<- uv_run_once\n")));
    EVENTLOOP_DEBUG_C((printf(" - handles: %d\n", uvloop->active_handles)));
    [pool drain];
  }
}

int main(int argc, char** argv) {
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];  // Make sure NSApp is initialized.

  InitMenuBar();
  plaskAppDelegate* app_delegate = [[plaskAppDelegate alloc] init];
  [NSApp setDelegate:app_delegate];

  char* bundled_argv[] = {argv[0], NULL};
  NSString* bundled_main_js =
      [[NSBundle mainBundle] pathForResource:@"main" ofType:@"js"];
  if (bundled_main_js != nil) {
    argc = 2;
    bundled_argv[1] = strdup([bundled_main_js UTF8String]);
    argv = bundled_argv;
    NSLog(@"loading from bundled: %@", bundled_main_js);
  }

  argv = uv_setup_args(argc, argv);
  argv = node::Init(argc, argv);

  v8::V8::Initialize();
  {
    v8::Locker locker;
    v8::HandleScope handle_scope;

    // Create the one and only Context.
    v8::Persistent<v8::Context> context = v8::Context::New();
    v8::Context::Scope context_scope(context);

    v8::Handle<v8::Object> process = node::SetupProcessObject(argc, argv);
    v8_typed_array::AttachBindings(context->Global());

    v8::Handle<v8::ObjectTemplate> plask_raw = v8::ObjectTemplate::New();
    plask_setup_bindings(plask_raw);
    context->Global()->Set(v8::String::NewSymbol("PlaskRawMac"),
                           plask_raw->NewInstance());

    node::Load(process);

#if EVENTLOOP_BYPASS_CUSTOM
    uv_run(uv_default_loop());
#else
    // [NSApp run];
    [NSApp finishLaunching];
    [NSApp activateIgnoringOtherApps:YES];  // TODO(deanm): Do we want this?
    [NSApp setWindowsNeedUpdate:YES];
    RunMainLoop();
#endif

    node::EmitExit(process);

    // NOTE(deanm): Only used for DeleteSlabAllocator?
    // RunAtExit()

#ifndef NDEBUG
    context.Dispose();
#endif  // NDEBUG
  }

#ifndef NDEBUG
  v8::V8::Dispose();
#endif  // NDEBUG

  [pool release];
  return 0;
}
