#include <stdint.h>
#include <stdbool.h>
bool TouchStart(void (*onPinch)(void));
void TouchStop(void);
bool SystemPinchStart(void (*onPinch)(void));
void SystemPinchStop(void);
bool SystemPinchTrusted(void);
unsigned long SystemPinchSuppressionCount(void);
