#include "PinchRoute.h"
#include <math.h>

RouteDecision RouteSystemPinch(PinchOwner *owner, PinchPhase phase, double progress) {
    const int begin = phase == PinchBegin || phase == PinchMaybeBegin;
    const int end = phase == PinchEnd || phase == PinchCancel;
    if (!begin && !end && phase != PinchChanged) return RoutePass;
    if (begin) *owner = PinchUnclassified;
    if (!isfinite(progress)) {
        *owner = PinchSystem;
        return RoutePassWithBegin;
    }
    if (*owner == PinchUnclassified) {
        if (progress < -0.0001) *owner = PinchLauncher;
        else if (progress > 0.0001 || end) {
            *owner = end ? PinchUnclassified : PinchSystem;
            return RoutePassWithBegin;
        } else if (begin) return RouteHoldBegin;
        else return RouteConsume;
    }
    RouteDecision route = *owner == PinchLauncher ? RouteConsume : RoutePass;
    if (end) *owner = PinchUnclassified;
    return route;
}
