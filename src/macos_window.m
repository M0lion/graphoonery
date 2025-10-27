#include <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>

@interface WindowDelegate : NSObject <NSWindowDelegate>
@property(assign) BOOL shouldClose;
@end

@implementation WindowDelegate
- (void)windowWillClose:(NSNotification *)notification {
  self.shouldClose = YES;
}
@end

static WindowDelegate *windowDelegate = nil;

void *createMacWindow(void) {
  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  NSRect frame = NSMakeRect(100, 100, 800, 600);
  NSWindow *window = [[NSWindow alloc]
      initWithContentRect:frame
                styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskResizable)
                  backing:NSBackingStoreBuffered
                    defer:NO];

  windowDelegate = [[WindowDelegate alloc] init];
  windowDelegate.shouldClose = NO;
  [window setDelegate:windowDelegate];

  // Create Metal layer for Vulkan
  NSView *contentView = [window contentView];
  [contentView setWantsLayer:YES];
  CAMetalLayer *metalLayer = [CAMetalLayer layer];
  [contentView setLayer:metalLayer];

  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];

  return (__bridge_retained void *)window;
}

void *getMetalLayer(void *window) {
  NSWindow *nsWindow = (__bridge NSWindow *)window;
  NSView *contentView = [nsWindow contentView];
  return (__bridge void *)[contentView layer];
}

void getWindowSize(void *window, int *width, int *height) {
  NSWindow *nsWindow = (__bridge NSWindow *)window;
  NSRect frame = [[nsWindow contentView] frame];
  *width = (int)frame.size.width;
  *height = (int)frame.size.height;
}

typedef enum {
  EventTypeKeyDown = 10,
  EventTypeKeyUp = 11,
  EventTypeMouseDown = 1,
  EventTypeMouseUp = 2,
  EventTypeMouseMoved = 5,
  EventTypeScrollWheel = 22,
  EventTypeNone = 0,
} EventType;

typedef struct {
  EventType type;
  unsigned short keyCode;
  double mouseX;
  double mouseY;
  double deltaX;
  double deltaY;
} MacEvent;

bool pollMacEvent(MacEvent *outEvent) {
  if (windowDelegate.shouldClose) {
    return false;
  }

  NSEvent *event;
  while ((event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                     untilDate:nil
                                        inMode:NSDefaultRunLoopMode
                                       dequeue:YES])) {

    [NSApp sendEvent:event];
    [NSApp updateWindows];
  }

  outEvent->type = EventTypeNone;
  return true;
}

void releaseMacWindow(void *window) {
  windowDelegate = nil;
  NSWindow *nsWindow = (__bridge_transfer NSWindow *)window;
  nsWindow = nil;
}
