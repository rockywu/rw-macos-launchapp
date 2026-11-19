#include "Detector.h"
#include <math.h>
#include <string.h>

static void baseline(Detector *d, const Contact *p, int n, double t) {
    memcpy(d->start, p, (size_t)n * sizeof(*p));
    d->count = n;
    d->began = t;
    d->frames = 0;
}

bool DetectPinch(Detector *d, const Contact *p, int n, double t) {
    if (n < 0 || n > 5 || !isfinite(t)) { d->count = 0; return false; }
    if (n == 0) { *d = (Detector){0}; return false; }
    if (d->fired) return false;
    if (n < 4) { d->count = 0; return false; }

    if (d->count != n || t < d->began || t - d->began > 0.75) {
        baseline(d, p, n, t);
        return false;
    }
    Contact matched[5];
    float bx=0, by=0, x=0, y=0;
    for (int i=0; i<n; ++i) {
        int j=0;
        while (j<n && p[j].id != d->start[i].id) ++j;
        if (j==n) { baseline(d, p, n, t); return false; }
        matched[i]=p[j];
        bx+=d->start[i].x; by+=d->start[i].y; x+=p[j].x; y+=p[j].y;
    }
    bx/=n; by/=n; x/=n; y/=n;
    float initial=0, current=0;
    int inward=0;
    for (int i=0; i<n; ++i) {
        float a=hypotf(d->start[i].x-bx,d->start[i].y-by);
        float b=hypotf(matched[i].x-x,matched[i].y-y);
        initial+=a;
        current+=b;
        if (a-b > 0.017f) ++inward;
    }
    float change = (initial-current)/n;
    if (initial/n < 0.09f || current > initial*1.05f ||
        (t-d->began > 0.20 && change < 0.012f)) {
        baseline(d,p,n,t);
        return false;
    }
    bool pinching = current < initial * 0.77f && change > 0.030f &&
                    inward >= n-1 && hypotf(x-bx,y-by) < 0.075f + change &&
                    t - d->began >= 0.055;
    d->frames = pinching ? d->frames + 1 : 0;
    if (d->frames >= 2) { d->fired=true; return true; }
    return false;
}
