#import "RMXFirebase+RACSupport.h"
#import "RACScheduler.h"

@implementation RMXFirebase

+ (RACScheduler *)scheduler {
  return [RACScheduler schedulerWithPriority:RACSchedulerPriorityHigh];
}

@end
