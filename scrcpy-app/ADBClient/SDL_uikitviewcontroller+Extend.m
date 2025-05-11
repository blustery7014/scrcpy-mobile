//
//  SDL_uikitviewcontroller+Extend.m
//  Scrcpy Remote
//
//  Created by Ethan on 1/4/25.
//

#import "SDL_uikitviewcontroller+Extend.h"
#import <AVFoundation/AVFoundation.h>
#import "ScrcpyClientWrapper.h"
#import "ADBClient.h"

@implementation SDL_uikitviewcontroller (Extend)

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];
    for (CALayer *layer in self.view.layer.sublayers) {
        if ([layer isKindOfClass:AVSampleBufferDisplayLayer.class]) {
            layer.frame = self.view.bounds;
        }
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)dealloc
{
    for (UIWindowScene *scene in [[UIApplication sharedApplication] connectedScenes]) {
        NSLog(@"ViewController: %@, prefersHomeIndicatorAutoHidden: %d", scene.keyWindow.rootViewController, scene.keyWindow.rootViewController.prefersHomeIndicatorAutoHidden);
        [scene.keyWindow.rootViewController setNeedsUpdateOfHomeIndicatorAutoHidden];
    }
    NSLog(@"Reset ViewControllers HomeIndicatorAutoHidden.");
}

@end
