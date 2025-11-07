#include <AppKit/AppKit.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import "macos_types.h"

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

// Returns true if event was retrieved, false if no more events
bool pollMacEvent(MacEvent *outEvent) {
  if (windowDelegate.shouldClose) {
    return false;
  }

  NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                      untilDate:nil
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES];
  
  if (!event) {
    return false;  // No events available
  }

  // Process this one event
  [NSApp sendEvent:event];
  [NSApp updateWindows];

  // Convert to MacEvent
  switch (event.type) {
    case NSEventTypeKeyDown:
      outEvent->type = EventTypeKeyDown;
      outEvent->data.key.keyCode = event.keyCode;
      outEvent->data.key.modifiers = event.modifierFlags;
      outEvent->data.key.isRepeat = event.isARepeat;
      
      // Copy text
      NSString *chars = event.characters;
      if (chars && chars.length > 0) {
        const char *utf8 = [chars UTF8String];
        size_t len = strlen(utf8);
        if (len < sizeof(outEvent->data.key.text)) {
          memcpy(outEvent->data.key.text, utf8, len);
          outEvent->data.key.textLen = (unsigned char)len;
        } else {
          outEvent->data.key.textLen = 0;
        }
      } else {
        outEvent->data.key.textLen = 0;
      }
      return true;

    case NSEventTypeKeyUp:
      outEvent->type = EventTypeKeyUp;
      outEvent->data.key.keyCode = event.keyCode;
      outEvent->data.key.modifiers = event.modifierFlags;
      outEvent->data.key.isRepeat = false;
      outEvent->data.key.textLen = 0;
      return true;

    case NSEventTypeLeftMouseDown:
    case NSEventTypeRightMouseDown:
    case NSEventTypeOtherMouseDown:
      outEvent->type = EventTypeMouseDown;
      outEvent->data.mouse.x = event.locationInWindow.x;
      outEvent->data.mouse.y = event.locationInWindow.y;
      return true;

    case NSEventTypeLeftMouseUp:
    case NSEventTypeRightMouseUp:
    case NSEventTypeOtherMouseUp:
      outEvent->type = EventTypeMouseUp;
      outEvent->data.mouse.x = event.locationInWindow.x;
      outEvent->data.mouse.y = event.locationInWindow.y;
      return true;

    case NSEventTypeMouseMoved:
    case NSEventTypeLeftMouseDragged:
    case NSEventTypeRightMouseDragged:
    case NSEventTypeOtherMouseDragged:
      outEvent->type = EventTypeMouseMoved;
      outEvent->data.mouseMove.x = event.locationInWindow.x;
      outEvent->data.mouseMove.y = event.locationInWindow.y;
      outEvent->data.mouseMove.deltaX = event.deltaX;
      outEvent->data.mouseMove.deltaY = event.deltaY;
      return true;

    case NSEventTypeScrollWheel:
      outEvent->type = EventTypeScrollWheel;
      outEvent->data.scroll.deltaX = event.scrollingDeltaX;
      outEvent->data.scroll.deltaY = event.scrollingDeltaY;
      return true;

    default:
      // Ignore other event types, try next event
      return pollMacEvent(outEvent);  // Recursive call for next event
  }
}

void releaseMacWindow(void *window) {
  windowDelegate = nil;
  NSWindow *nsWindow = (__bridge_transfer NSWindow *)window;
  nsWindow = nil;
}
