// Exercise the production callback dispatcher without opening a trackpad device.
#include <pthread.h>
#include <assert.h>
#include <stdint.h>
#include "../../src/TouchBridge/TouchBridge.c"
static atomic_uint deliveries;
static void frame(const float *xy, int count, double timestamp) {
 (void)xy; (void)timestamp; assert(count == 0);
 atomic_fetch_add_explicit(&deliveries,1,memory_order_relaxed);
}
static void *change_consumer(void *argument) {
 (void)argument;
 for(unsigned i=0;i<200000;i++) atomic_store_explicit(&consumer,(i%2) ? frame : NULL,memory_order_release);
 return NULL;
}
static void *deliver(void *argument) {
 (void)argument;
 for(unsigned i=0;i<200000;i++) receive(0,NULL,0,0,0);
 return NULL;
}
int main(void) {
 atomic_store(&consumer,frame);receive(0,NULL,0,0,0);
 assert(atomic_load(&deliveries)==1);
 pthread_t writer,reader;
 assert(pthread_create(&writer,NULL,change_consumer,NULL)==0);
 assert(pthread_create(&reader,NULL,deliver,NULL)==0);
 pthread_join(writer,NULL);pthread_join(reader,NULL);
 hs_stop();unsigned stopped=atomic_load(&deliveries);receive(0,NULL,0,0,0);
 assert(atomic_load(&deliveries)==stopped);
 return 0;
}
