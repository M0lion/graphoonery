#import <Cocoa/Cocoa.h>

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

  [window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];

  return (__bridge_retained void *)window;
}

// Event types matching NSEventType
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

  NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                                      untilDate:nil
                                         inMode:NSDefaultRunLoopMode
                                        dequeue:YES];

  if (!event) {
    outEvent->type = EventTypeNone;
    return true;
  }

  [NSApp sendEvent:event];

  outEvent->type = (EventType)[event type];

  switch ([event type]) {
  case NSEventTypeKeyDown:
  case NSEventTypeKeyUp:
    outEvent->keyCode = [event keyCode];
    break;

  case NSEventTypeLeftMouseDown:
  case NSEventTypeLeftMouseUp:
  case NSEventTypeRightMouseDown:
  case NSEventTypeRightMouseUp:
  case NSEventTypeMouseMoved:
  case NSEventTypeLeftMouseDragged:
  case NSEventTypeRightMouseDragged: {
    NSPoint location = [event locationInWindow];
    outEvent->mouseX = location.x;
    outEvent->mouseY = location.y;
    break;
  }

  case NSEventTypeScrollWheel:
    outEvent->deltaX = [event scrollingDeltaX];
    outEvent->deltaY = [event scrollingDeltaY];
    break;

  default:
    break;
  }

  return true;
}

void releaseMacWindow(void *window) {
  windowDelegate = nil;
  NSWindow *nsWindow = (__bridge_transfer NSWindow *)window;
  nsWindow = nil;
}
