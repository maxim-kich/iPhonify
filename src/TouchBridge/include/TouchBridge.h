#pragma once
// Private contact ABI; resolved dynamically, no system modifications.
typedef void (*HSFrame)(const float *xy, int count, double timestamp);
int hs_start(HSFrame callback);
void hs_stop(void);
int hs_space_swipe(int direction, int augmented);

