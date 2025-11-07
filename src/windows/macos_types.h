// macos_events.h
#ifndef MACOS_EVENTS_H
#define MACOS_EVENTS_H

#include <stdbool.h>

typedef enum {
  EventTypeKeyDown,
  EventTypeKeyUp,
  EventTypeMouseDown,
  EventTypeMouseUp,
  EventTypeMouseMoved,
  EventTypeScrollWheel,
} EventType;

typedef struct {
  unsigned short keyCode;
  unsigned int modifiers;
  bool isRepeat;
  char text[16];
  unsigned char textLen;
} KeyEventData;

typedef struct {
  double x;
  double y;
} MouseEventData;

typedef struct {
  double x;
  double y;
  double deltaX;
  double deltaY;
} MouseMoveEventData;

typedef struct {
  double deltaX;
  double deltaY;
} ScrollEventData;

typedef struct {
  EventType type;
  union {
    KeyEventData key;
    MouseEventData mouse;
    MouseMoveEventData mouseMove;
    ScrollEventData scroll;
  } data;
} MacEvent;

bool pollMacEvent(MacEvent *outEvent);

#endif
