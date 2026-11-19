#pragma once
#include <stdbool.h>
typedef struct { int id; float x, y; } Contact;
typedef struct {
    Contact start[5];
    int count;
    int frames;
    double began;
    bool fired;
} Detector;
bool DetectPinch(Detector *d, const Contact *p, int count, double time);
