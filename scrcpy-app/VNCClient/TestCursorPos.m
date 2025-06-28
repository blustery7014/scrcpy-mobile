#import <Foundation/Foundation.h>
#import "CursorPosManager.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        CursorPosManager *manager = [[CursorPosManager alloc] init];
        
        NSLog(@"Initial underlyingPos: %@", NSStringFromPoint(manager.underlyingPos));
        NSLog(@"Initial displayPos: %@", NSStringFromPoint(manager.displayPos));

        manager.localScreenSize = CGSizeMake(800, 600);
        manager.remoteScreenSize = CGSizeMake(1920, 1080);

        NSLog(@"Local screen size: %@", NSStringFromSize(manager.localScreenSize));
        NSLog(@"Remote screen size: %@", NSStringFromSize(manager.remoteScreenSize));

        // Simulate a drag gesture
        NSLog(@"\n--- Begin Drag ---");
        [manager beginMove:CGPointMake(10, 10)];
        
        NSLog(@"\n--- Dragging ---");
        [manager moveTo:CGPointMake(20, 25)];
        NSLog(@"displayPos during drag: %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"remoteCursorPos during drag: %@", NSStringFromPoint(manager.remoteCursorPos));

        [manager moveTo:CGPointMake(5, 0)];
        NSLog(@"displayPos during drag: %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"remoteCursorPos during drag: %@", NSStringFromPoint(manager.remoteCursorPos));

        NSLog(@"\n--- End Drag ---");
        [manager stopMove];
        
        NSLog(@"Final underlyingPos: %@", NSStringFromPoint(manager.underlyingPos));
        NSLog(@"Final displayPos: %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"Final remoteCursorPos: %@", NSStringFromPoint(manager.remoteCursorPos));
        
        // Simulate another drag gesture
        NSLog(@"\n--- Begin Drag 2 ---");
        [manager beginMove:CGPointMake(100, 100)];
        
        NSLog(@"\n--- Dragging 2 ---");
        [manager moveTo:CGPointMake(110, 110)];
        NSLog(@"displayPos during drag: %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"remoteCursorPos during drag: %@", NSStringFromPoint(manager.remoteCursorPos));
        
        NSLog(@"\n--- End Drag 2 ---");
        [manager stopMove];
        
        NSLog(@"Final underlyingPos: %@", NSStringFromPoint(manager.underlyingPos));
        NSLog(@"Final displayPos: %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"Final remoteCursorPos: %@", NSStringFromPoint(manager.remoteCursorPos));

        // Test boundary conditions
        NSLog(@"\n--- Begin Boundary Test ---");
        manager.underlyingPos = CGPointMake(900, 700); // Out of local bounds
        NSLog(@"underlyingPos out of bounds: %@", NSStringFromPoint(manager.underlyingPos));
        NSLog(@"remoteCursorPos (clamped): %@", NSStringFromPoint(manager.remoteCursorPos));

        manager.underlyingPos = CGPointMake(-100, -100); // Negative out of bounds
        NSLog(@"underlyingPos out of bounds (negative): %@", NSStringFromPoint(manager.underlyingPos));
        NSLog(@"remoteCursorPos (clamped): %@", NSStringFromPoint(manager.remoteCursorPos));

        // Test dragging past the boundary
        NSLog(@"\n--- Begin Drag Past Boundary ---");
        [manager beginMove:CGPointMake(790, 590)];
        [manager moveTo:CGPointMake(810, 610)]; // Move past the boundary
        NSLog(@"displayPos during drag (clamped): %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"remoteCursorPos during drag (clamped): %@", NSStringFromPoint(manager.remoteCursorPos));
        [manager stopMove];
        NSLog(@"Final displayPos after drag (clamped): %@", NSStringFromPoint(manager.displayPos));
        NSLog(@"Final remoteCursorPos after drag (clamped): %@", NSStringFromPoint(manager.remoteCursorPos));
    }
    return 0;
}