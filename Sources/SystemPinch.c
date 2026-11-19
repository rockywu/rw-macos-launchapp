#include "TouchBridge.h"
#include "PinchRoute.h"
#include <ApplicationServices/ApplicationServices.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <stdint.h>

static CFMachPortRef eventTap;
static CFRunLoopSourceRef source;
static CGEventRef pendingBegin;
static PinchOwner owner;
static CFTypeRef (*copyHID)(CGEventRef);
static uint32_t (*hidType)(CFTypeRef);
static int64_t (*hidInt)(CFTypeRef, uint32_t);
static double (*hidFloat)(CFTypeRef, uint32_t);
static uint16_t (*hidPhase)(CFTypeRef);
static unsigned long suppressionCount;
static double inwardProgress;
static void (*notifyPinch)(void);

static void clearPending(void) {
    if (pendingBegin) CFRelease(pendingBegin);
    pendingBegin = NULL;
}

/* IOKit DockSwipe fields. See Mac Mouse Fix Tests/FixDockSwipes.m for
 * macOS 27's HID-backed events; CG event fields are the older fallback. */
static bool extractPinch(CGEventRef event, PinchPhase *phase, double *progress) {
    const int dockSwipe = 23, scale = 3, dockPrimary = 3;
    const uint32_t field = dockSwipe << 16;
    if (copyHID && hidType && hidInt && hidFloat && hidPhase) {
        CFTypeRef hid = copyHID(event);
        if (hid) {
            uint32_t type = hidType(hid);
            bool match = type == dockSwipe && hidInt(hid, field+1) == scale &&
                         hidInt(hid, field+5) == dockPrimary;
            if (match) {
                *progress = hidFloat(hid, field+2);
                *phase = (PinchPhase)hidPhase(hid);
            }
            CFRelease(hid);
            if (type == dockSwipe) return match;
        }
    }
    if (CGEventGetIntegerValueField(event, (CGEventField)110) != dockSwipe ||
        CGEventGetIntegerValueField(event, (CGEventField)123) != scale) return false;
    *phase = (PinchPhase)CGEventGetIntegerValueField(event, (CGEventField)132);
    *progress = CGEventGetDoubleValueField(event, (CGEventField)124);
    return true;
}

static CGEventRef eventCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *context) {
    (void)context;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        clearPending();
        owner = PinchUnclassified;
        inwardProgress = 0;
        if (eventTap) CGEventTapEnable(eventTap, true);
        return event;
    }
    PinchPhase phase;
    double progress;
    if (type != (CGEventType)30 || !extractPinch(event, &phase, &progress)) return event;
    if (phase == PinchBegin || phase == PinchMaybeBegin) {
        inwardProgress = 0;
        clearPending();
    }
    PinchOwner previous = owner;
    switch (RouteSystemPinch(&owner, phase, progress)) {
        case RouteHoldBegin:
            pendingBegin = (CGEventRef)CFRetain(event);
            return NULL;
        case RoutePassWithBegin:
            if (pendingBegin) {
                CGEventTapPostEvent(proxy, pendingBegin);
                clearPending();
            }
            return event;
        case RouteConsume:
            if (owner == PinchLauncher || previous == PinchLauncher || phase == PinchEnd || phase == PinchCancel) {
                if (previous != PinchLauncher && progress < 0) ++suppressionCount;
                if (-progress > inwardProgress) inwardProgress = -progress;
                if (phase == PinchEnd && inwardProgress >= 0.20 && notifyPinch) notifyPinch();
                if (phase == PinchEnd || phase == PinchCancel) inwardProgress = 0;
                clearPending();
            }
            return NULL;
        case RoutePass:
            if (pendingBegin) {
                CGEventTapPostEvent(proxy, pendingBegin);
                clearPending();
            }
            return event;
    }
    return event;
}

bool SystemPinchStart(void (*onPinch)(void)) {
    if (eventTap) return CGEventTapIsEnabled(eventTap);
    if (!AXIsProcessTrusted()) return false;
    notifyPinch = onPinch;
    copyHID = dlsym(RTLD_DEFAULT, "CGEventCopyIOHIDEvent");
    hidType = dlsym(RTLD_DEFAULT, "IOHIDEventGetType");
    hidInt = dlsym(RTLD_DEFAULT, "IOHIDEventGetIntegerValue");
    hidFloat = dlsym(RTLD_DEFAULT, "IOHIDEventGetFloatValue");
    hidPhase = dlsym(RTLD_DEFAULT, "IOHIDEventGetPhase");
    eventTap = CGEventTapCreate(kCGSessionEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault,
                                CGEventMaskBit(30), eventCallback, NULL);
    if (!eventTap) return false;
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    if (!source) { SystemPinchStop(); return false; }
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    CGEventTapEnable(eventTap, true);
    return CGEventTapIsEnabled(eventTap);
}

void SystemPinchStop(void) {
    notifyPinch = NULL;
    inwardProgress = 0;
    clearPending();
    owner = PinchUnclassified;
    if (source) {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
        CFRelease(source);
        source = NULL;
    }
    if (eventTap) {
        CGEventTapEnable(eventTap, false);
        CFMachPortInvalidate(eventTap);
        CFRelease(eventTap);
        eventTap = NULL;
    }
}

bool SystemPinchTrusted(void) { return AXIsProcessTrusted(); }
unsigned long SystemPinchSuppressionCount(void) { return suppressionCount; }
