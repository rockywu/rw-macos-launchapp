#include "TouchBridge.h"
#include "Detector.h"
#include <CoreFoundation/CoreFoundation.h>
#include <CoreServices/CoreServices.h>
#include <dlfcn.h>
#include <math.h>
#include <pthread.h>
#include "OpenMTInternal.h"

static void *library;
static MTDeviceRef device;
static MTDeviceRef (*createDefault)(void);
static void (*registerFrame)(MTDeviceRef, MTFrameCallbackFunction);
static void (*unregisterFrame)(MTDeviceRef, MTFrameCallbackFunction);
static OSStatus (*startDevice)(MTDeviceRef,int);
static OSStatus (*stopDevice)(MTDeviceRef);
static void (*releaseDevice)(MTDeviceRef);
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static MTDeviceRef active;
static Detector detector;
static void (*handler)(void);

static void frame(MTDeviceRef source, MTTouch *touches, int n, double t, int frameNumber) {
    (void)frameNumber;
    if (n<0 || n>32 || (n>0 && !touches)) return;
    Contact p[5];
    int count=0;
    for (int i=0;i<n;i++) {
        if (touches[i].state != MTTouchStateMakeTouch && touches[i].state != MTTouchStateTouching) continue;
        MTPoint q=touches[i].normalizedPosition.position;
        if (!isfinite(q.x) || !isfinite(q.y) || q.x < -0.1f || q.x > 1.1f || q.y < -0.1f || q.y > 1.1f) return;
        if (count==5) { count=6; break; }
        p[count++]=(Contact){touches[i].identifier,q.x,q.y};
    }
    pthread_mutex_lock(&lock);
    void (*notify)(void) = source == active && DetectPinch(&detector,p,count,t) ? handler : NULL;
    pthread_mutex_unlock(&lock);
    if (notify) notify();
}

bool TouchStart(void (*onPinch)(void)) {
    if (device) return true;
    if (!library) {
        library=dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_LAZY|RTLD_LOCAL);
        if (!library) return false;
        createDefault=dlsym(library,"MTDeviceCreateDefault");
        registerFrame=dlsym(library,"MTRegisterContactFrameCallback");
        unregisterFrame=dlsym(library,"MTUnregisterContactFrameCallback");
        startDevice=dlsym(library,"MTDeviceStart");
        stopDevice=dlsym(library,"MTDeviceStop");
        releaseDevice=dlsym(library,"MTDeviceRelease");
    }
    if (!createDefault || !registerFrame || !unregisterFrame || !startDevice || !stopDevice || !releaseDevice) return false;
    device=createDefault();
    if (!device) return false;
    pthread_mutex_lock(&lock);
    active=device; handler=onPinch; detector=(Detector){0};
    pthread_mutex_unlock(&lock);
    registerFrame(device,frame);
    if (startDevice(device,0) == 0) return true;
    TouchStop();
    return false;
}

void TouchStop(void) {
    if (!device) return;
    pthread_mutex_lock(&lock);
    active=NULL; handler=NULL;
    pthread_mutex_unlock(&lock);
    unregisterFrame(device,frame);
    stopDevice(device);
    releaseDevice(device);
    device=NULL;
}
