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

#import <Cocoa/Cocoa.h>

#import "plaskAppDelegate.h"

#include "plask_bindings.h"

#include "v8.h"
#define EV_MULTIPLICITY 0
#include "node.h"
#include "ev.h"

static void TimerFired(CFRunLoopTimerRef timer, void* info);

static void PumpNode() {
  ev_now_update();  // Bring the clock forward since the last ev_loop().
  ev_loop(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
  while(ev_backend_changecount() != 0) {
    ev_loop(EV_DEFAULT_UC_ EVLOOP_NONBLOCK);
  }
}

static void KqueueCallback(CFFileDescriptorRef backend_cffd,
                           CFOptionFlags callBackTypes,
                           void* info) {
  PumpNode();
  CFFileDescriptorEnableCallBacks(backend_cffd, kCFFileDescriptorReadCallBack);
}

static void RunMainLoop() {
  // TODO Probably don't need to start this each time.
  // Avoids failing on test/simple/test-eio-race3.js though
  // ev_idle_start(EV_DEFAULT_UC_ &eio_poller);

  // Make sure the kqueue is initialized and the kernel state is up to date.
  PumpNode();

  int backend_fd = ev_backend_fd();

  CFFileDescriptorRef backend_cffd =
      CFFileDescriptorCreate(NULL, backend_fd, true, &KqueueCallback, NULL);
  CFRunLoopSourceRef backend_rlsr =
      CFFileDescriptorCreateRunLoopSource(NULL, backend_cffd, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(),
                     backend_rlsr,
                     kCFRunLoopDefaultMode);
  CFRelease(backend_rlsr);
  CFFileDescriptorEnableCallBacks(backend_cffd, kCFFileDescriptorReadCallBack);

  [NSApp finishLaunching];

  [NSApp activateIgnoringOtherApps:YES];  // TODO(deanm): Do we want this?
  [NSApp setWindowsNeedUpdate:YES];

  while (true) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    PumpNode();
    double next_waittime = ev_next_waittime();
    // TODO(deanm): Fix loop integration with newest version of Node.
    next_waittime = 0.01;
    NSDate* next_date = [NSDate dateWithTimeIntervalSinceNow:next_waittime];
    // printf("Running a loop iteration with timeout %f\n", next_waittime);
    NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
                            untilDate:next_date
                            inMode:NSDefaultRunLoopMode // kCFRunLoopDefaultMode
                            dequeue:YES];
    if (event != nil) {  // event is nil on a timeout.
      // NSLog(@"Event: %@\n", event);

      // A custom event to terminate, see applicationShouldTerminate.
      if ([event type] == NSApplicationDefined && [event subtype] == 37)
        return;

      [event retain];
      [NSApp sendEvent:event];
      [event release];
    }
    [pool drain];
  }
}

int main(int argc, char** argv) {  
  NSAutoreleasePool* pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];  // Make sure NSApp is initialized.
  
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

  argv = node::Init(argc, argv);
  v8::V8::Initialize();
  v8::HandleScope handle_scope;

  // Create the one and only Context.
  v8::Persistent<v8::Context> context = v8::Context::New();
  v8::Context::Scope context_scope(context);

  v8::Handle<v8::Object> process = node::SetupProcessObject(argc, argv);

  v8::Handle<v8::ObjectTemplate> plask_raw = v8::ObjectTemplate::New();
  plask_setup_bindings(plask_raw);

  context->Global()->Set(v8::String::NewSymbol("PlaskRawMac"),
                         plask_raw->NewInstance());

  node::Load(process);

  RunMainLoop();

  node::EmitExit(process);

#ifndef NDEBUG
  // Clean up.
  context.Dispose();
  v8::V8::Dispose();
#endif  // NDEBUG
  
  [pool release];
  return 0;
}
