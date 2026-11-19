#include "Detector.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

static void points(Contact *p, int n, float radius, float dx, float dy, int reverse) {
    for (int i=0; i<n; ++i) {
        double theta = 2 * acos(-1.0) * i / n;
        p[reverse ? n-i-1 : i] = (Contact){ i+1, dx+0.5f+radius*cos(theta), dy+0.5f+radius*sin(theta) };
    }
}

static void valid_pinches(int n) {
    Detector d={0}; Contact p[5];
    for (int round=0; round<2; ++round) {
        double t=1.0+round;
        points(p,n,0.22,0,0,0); assert(!DetectPinch(&d,p,n,t));
        points(p,n,0.13,0.02,0.01,1); assert(!DetectPinch(&d,p,n,t+0.10));
        assert(DetectPinch(&d,p,n,t+0.12));
        assert(!DetectPinch(&d,p,n,t+0.14));
        assert(!DetectPinch(&d,p,n-1,t+0.16));
        assert(!DetectPinch(&d,p,n,t+0.18));
        assert(!DetectPinch(&d,p,0,t+0.20));
    }
}

static void reject_non_pinches(void) {
    Detector d={0}; Contact p[5];
    points(p,3,0.25,0,0,0); assert(!DetectPinch(&d,p,3,1.0));
    points(p,3,0.05,0,0,0); assert(!DetectPinch(&d,p,3,1.10));
    assert(!DetectPinch(&d,p,3,1.12));
    points(p,4,0.22,0,0,0); assert(!DetectPinch(&d,p,4,2.0));
    points(p,4,0.22,0.12,0.04,0); assert(!DetectPinch(&d,p,4,2.10));
    assert(!DetectPinch(&d,p,4,2.12));
    points(p,4,0.30,0,0,0); assert(!DetectPinch(&d,p,4,2.14));
    assert(!DetectPinch(&d,p,4,2.16));
    points(p,4,0.12,0,0,0);
    assert(!DetectPinch(&d,p,6,2.18));
    assert(!DetectPinch(&d,p,4,2.20));
    assert(!DetectPinch(&d,p,4,2.22));
    points(p,4,0.25,0,0,0); assert(!DetectPinch(&d,p,4,3.1));
    points(p,4,0.11,0,0,0); p[0].id=123;
    assert(!DetectPinch(&d,p,4,3.25));
    assert(!DetectPinch(&d,p,4,3.27));
}

int main(void) {
    valid_pinches(4); valid_pinches(5); reject_non_pinches();
    puts("4/5-finger pinch, release, deduplication, swipe, spread, changed contacts and wrong finger counts: passed");
}
