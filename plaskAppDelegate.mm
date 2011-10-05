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

#import "plaskAppDelegate.h"

@implementation plaskAppDelegate

@synthesize window;

// We're running nibless, so we don't have the typical MainMenu.nib.  This code
// sets up the "Apple Menu", the menu in the menu bar with your application
// title, next to the actual apple logo menu.  It is a bit of a mess to create
// it programmatically.  For example, see:
//    http://lapcatsoftware.com/blog/2007/06/17/
static void InitMenuBar() {
  // Our NSApplication is created with an empty mainMenu.
  NSMenu* mainMenu = [[NSMenu alloc] init];
  [NSApp setMainMenu:mainMenu];
  [mainMenu release];

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
  if ([NSApp respondsToSelector:@selector(setAppleMenu:)]) {
    [NSApp performSelector:@selector(setAppleMenu:) withObject:menu];
  }
  [container_item release];
  [menu release];
}

-(void)applicationWillFinishLaunching:(NSNotification *)aNotification {
  InitMenuBar();
}

-(void)applicationDidFinishLaunching:(NSNotification *)aNotification {
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)app {
  // Handle shutdown by leaving the main loop instead of the default behavior
  // of exit() being called.
  [app postEvent:[NSEvent otherEventWithType:NSApplicationDefined
                                    location:NSMakePoint(0, 0)
                               modifierFlags:0
                                   timestamp:0
                                windowNumber:0
                                     context:nil
                                     subtype:37  // Arbitrary
                                       data1:0
                                       data2:0] atStart:YES];
  return NSTerminateCancel;
}

@end
