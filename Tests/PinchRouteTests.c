#include "PinchRoute.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    PinchOwner owner=PinchUnclassified;
    assert(RouteSystemPinch(&owner, PinchBegin, 0) == RouteHoldBegin);
    assert(RouteSystemPinch(&owner, PinchChanged, -0.08) == RouteConsume);
    assert(RouteSystemPinch(&owner, PinchChanged, 0.02) == RouteConsume);
    assert(RouteSystemPinch(&owner, PinchEnd, 0) == RouteConsume);
    assert(owner == PinchUnclassified);
    assert(RouteSystemPinch(&owner, PinchBegin, 0) == RouteHoldBegin);
    assert(RouteSystemPinch(&owner, PinchChanged, +0.08) == RoutePassWithBegin);
    assert(RouteSystemPinch(&owner, PinchChanged, -0.01) == RoutePass);
    assert(RouteSystemPinch(&owner, PinchCancel, 0) == RoutePass);
    assert(RouteSystemPinch(&owner, PinchBegin, 0) == RouteHoldBegin);
    assert(RouteSystemPinch(&owner, PinchEnd, 0) == RoutePassWithBegin);
    assert(RouteSystemPinch(&owner, PinchBegin, NAN) == RoutePassWithBegin);
    assert(RouteSystemPinch(&owner, (PinchPhase)63, -20) == RoutePass);
    puts("Pinch route suppresses inward only, passes outward and unknown phases: passed");
}
