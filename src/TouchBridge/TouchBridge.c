#include "TouchBridge.h"
#include <dlfcn.h>
#include <stddef.h>
#include <stdatomic.h>
typedef struct { float x,y; } Point;
typedef struct { Point position,velocity; } Vector;
typedef struct {
 int frame; double timestamp; int identifier,state,fingerID,handID;
 Vector normalized; float size; int unused; float angle,major,minor;
 Vector absolute; int unused2[2]; float density;
} Contact;
static void *library,*device;
static _Atomic(HSFrame) consumer;
static void (*stopDevice)(void*);
static void (*unregisterFrame)(void*,void*);
static int receive(int source, Contact *contacts, int count, double timestamp, int frame) {
 float xy[32]; int n=0;
 for(int i=0;i<count && n<16;i++) {
  Contact c=contacts[i];
  if(c.state==0 || c.state==7 || c.size<=0) continue;
  xy[2*n]=c.normalized.position.x; xy[2*n+1]=c.normalized.position.y; n++;
 }
 HSFrame callback=atomic_load_explicit(&consumer,memory_order_acquire);
 if(callback) callback(xy,n,timestamp);
 return 0;
}
int hs_start(HSFrame callback) {
 if(device) return 1;
 library=dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",RTLD_NOW);
 if(!library) return 0;
 void *(*create)(void)=dlsym(library,"MTDeviceCreateDefault");
 void (*reg)(void*,void*)=dlsym(library,"MTRegisterContactFrameCallback");
 void (*start)(void*,int)=dlsym(library,"MTDeviceStart");
 stopDevice=dlsym(library,"MTDeviceStop");
 unregisterFrame=dlsym(library,"MTUnregisterContactFrameCallback");
 if(!create || !reg || !start || !stopDevice || !unregisterFrame) return 0;
 device=create(); if(!device) return 0;
 atomic_store_explicit(&consumer,callback,memory_order_release); reg(device,receive); start(device,0); return 1;
}
void hs_stop(void) {
 atomic_store_explicit(&consumer,NULL,memory_order_release);
 if(device) { stopDevice(device); unregisterFrame(device,receive); device=NULL; }
 // Keep the framework loaded: late callbacks must remain safe.
}
