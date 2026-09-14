#import "VAppEmbed.h"

// VAppRootVC 在 VAppMain.m 中实现
@interface VAppRootVC : UITabBarController
@end

@implementation VAppEmbed

+ (UIViewController *)rootViewController {
    return [[VAppRootVC alloc] init];
}

@end
