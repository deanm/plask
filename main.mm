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
#include "uv.h"

#include "v8_typed_array.h"

static void TimerFired(CFRunLoopTimerRef timer, void* info);

static int PumpNode(uv_loop_t* uvloop) {
  // printf("  -> Pump Pump\n");
  int res = uv_run_once_really(uvloop);
  // printf("  %d\n", res);
  // printf("<-\n");
  return res;
}

static void KqueueCallback(CFFileDescriptorRef backend_cffd,
                           CFOptionFlags callBackTypes,
                           void* info) {
  // printf(" kqueue flagged\n");
  PumpNode(uv_default_loop());
  CFFileDescriptorEnableCallBacks(backend_cffd, kCFFileDescriptorReadCallBack);

  [NSApp postEvent:[NSEvent otherEventWithType:NSApplicationDefined
                                      location:NSMakePoint(0, 0)
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                       subtype:8  // Arbitrary
                                         data1:0
                                         data2:0] atStart:YES];
}

static void RunMainLoop() {
  // TODO Probably don't need to start this each time.
  // Avoids failing on test/simple/test-eio-race3.js though
  // ev_idle_start(EV_DEFAULT_UC_ &eio_poller);

  uv_loop_t* uvloop = uv_default_loop();

  // Make sure the kqueue is initialized and the kernel state is up to date.
  PumpNode(uvloop);

  int backend_fd = uv_backend_fd(uvloop);

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

  bool do_quit = false;
  while (!do_quit) {
    NSAutoreleasePool* pool = [NSAutoreleasePool new];
    if (PumpNode(uvloop) == 0) break;

    double ts = 9999;  // Timeout in seconds.  Default to some "future".
    int uv_waittime = uv_backend_timeout(uvloop);
    if (uv_waittime != -1)
      ts = uv_waittime / 1000.0;

    // printf("Running a loop iteration with timeout %f\n", ts);

    NSEvent* event = [NSApp nextEventMatchingMask:NSAnyEventMask
                            untilDate:[NSDate dateWithTimeIntervalSinceNow:ts]
                            inMode:NSDefaultRunLoopMode // kCFRunLoopDefaultMode
                            dequeue:YES];
    // printf("Done done.\n");
    if (event != nil) {  // event is nil on a timeout.
      // NSLog(@"Event: %@\n", event);

      // A custom event to terminate, see applicationShouldTerminate.
      if ([event type] == NSApplicationDefined && [event subtype] == 37) {
        do_quit = true;
      } else if ([event type] == NSApplicationDefined && [event subtype] == 8) {
        // A wakeup after the kqueue callback.
      } else {
        [event retain];
        [NSApp sendEvent:event];
        [event release];
      }
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

    // uv_run(uv_default_loop()).
    RunMainLoop();

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
