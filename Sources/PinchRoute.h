#pragma once
typedef enum { RoutePass, RouteHoldBegin, RoutePassWithBegin, RouteConsume } RouteDecision;
typedef enum { PinchUnclassified, PinchSystem, PinchLauncher } PinchOwner;
typedef enum { PinchBegin=1, PinchChanged=2, PinchEnd=4, PinchCancel=8, PinchMaybeBegin=128 } PinchPhase;
RouteDecision RouteSystemPinch(PinchOwner *owner, PinchPhase phase, double progress);
