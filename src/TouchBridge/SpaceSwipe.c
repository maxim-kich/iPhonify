// DockControl field mapping: InstantSpaceSwitcher (jurplel, MIT).
// Serialization in vendor/ is unmodified upstream code; see docs/licenses.
#include "TouchBridge.h"
#include "vendor/event_serialize.h"
#include <ApplicationServices/ApplicationServices.h>
#include <float.h>
int hs_space_swipe(int direction, int augmented) {
 double sign=direction < 0 ? -1.0 : 1.0;
 if(augmented) {
  Boolean valid=0;
  Boolean natural=CFPreferencesGetAppBooleanValue(CFSTR("com.apple.swipescrolldirection"),kCFPreferencesAnyApplication,&valid);
  sign=-sign*((!valid || natural) ? 1 : -1);
 }
 const int phases[]={1,2,4};
 for(int i=0;i<3;i++) {
  const int phase = phases[i];
  CGEventRef e=CGEventCreate(NULL); if(!e) return 0;
  CGEventSetIntegerValueField(e,(CGEventField)55,30);
  CGEventSetIntegerValueField(e,(CGEventField)110,23);
  CGEventSetIntegerValueField(e,(CGEventField)123,1);
  CGEventSetIntegerValueField(e,(CGEventField)132,phase);
  // Pre-27 WindowServer needs real Changed progress to prepare destination
  // surfaces. Zero-travel commits can leave otherwise valid windows unpainted.
  // ISS PR #105. Preserve the separate, unverified macOS 27 payload.
  double progress = augmented ? 0.000016 : (i == 0 ? (double)FLT_TRUE_MIN : 1.0);
  CGEventSetDoubleValueField(e,(CGEventField)124,sign*progress);
  if(!augmented || i==2) CGEventSetDoubleValueField(e,(CGEventField)129,sign*(augmented ? 9999 : 2000));
  if(!augmented) CGEventSetDoubleValueField(e,(CGEventField)130,sign*2000);
  if(augmented) {
   CGEventSetIntegerValueField(e,(CGEventField)134,phase);
   CGEventSetDoubleValueField(e,(CGEventField)125,0.1);
   CGEventRef a=iss_augment_dock_swipe_event(e);
   CFRelease(e); if(!a) return 0;
   CGEventPost(kCGSessionEventTap,a); CFRelease(a);
   e=CGEventCreate(NULL);if(!e) return 0;CGEventSetIntegerValueField(e,(CGEventField)55,29);
  }
  CGEventPost(kCGSessionEventTap,e); CFRelease(e);
 }
 return 1;
}


