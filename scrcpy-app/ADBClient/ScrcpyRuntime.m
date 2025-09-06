//
//  ScrcpyRuntime.m
//  Scrcpy Remote
//
//  Created by Ethan on 1/1/25.
//
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <math.h>
#import <libavutil/frame.h>
#import "ScrcpyRuntime.h"
#import "scrcpy-porting.h"
#import "app/config.h"

typedef enum : NSUInteger {
    // 0: disable hardware decoding
    ScrcpyHardwareDecodingDisabled = 0,
    // 1: enable hardware decoding with layer render
    ScrcpyHardwareDecodingLayerRender = 1,
    // 2: enable hardware decoding with sdl render
    ScrcpyHardwareDecodingSDLRender = 2,
} ScrcpyHardwareDecodingType;

const char *ScrcpyCoreVersion(void)
{
    return SCRCPY_VERSION;
}

float ScrcpyRenderScreenScale(void)
{
    return [UIScreen mainScreen].nativeScale;
}

int ScrcpyEnableHardwareDecoding(void)
{
    // To enable hardware decoding if target not simulator
    return TARGET_OS_SIMULATOR ? ScrcpyHardwareDecodingDisabled : ScrcpyHardwareDecodingLayerRender;
}

float ScrcpyAudioVolumeScale(float update_scale)
{
    static float volume_scale = 1.0f;
    volume_scale = update_scale > 0 ? update_scale : volume_scale;
    return volume_scale;
}

AVSampleBufferDisplayLayer *GetSampleBufferDisplayLayer(void)
{
    @autoreleasepool {
        static AVSampleBufferDisplayLayer *displayLayer = nil;
        if (displayLayer != nil && displayLayer.superlayer != nil) {
            return displayLayer;
        }
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            @autoreleasepool {
                [displayLayer removeFromSuperlayer];
                displayLayer = [AVSampleBufferDisplayLayer layer];
                displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;
                
                UIWindow *sdlWindow = GetCurrentWindowScene().keyWindow;
                
                // Skip when no SDL window found
                if (sdlWindow == nil) {
                    return;
                }
                
                displayLayer.frame = sdlWindow.rootViewController.view.bounds;
                [sdlWindow.rootViewController.view.layer addSublayer:displayLayer];
                sdlWindow.rootViewController.view.backgroundColor = UIColor.blackColor;
                // sometimes failed to set background color, so we append to next runloop
                displayLayer.backgroundColor = UIColor.blackColor.CGColor;
            }
        });

        return displayLayer;
    }
}

void RenderPixelBufferFrame(CVPixelBufferRef pixelBuffer) {
    @autoreleasepool {
        if (pixelBuffer == NULL) { return; }
        
        CMSampleTimingInfo timing = {kCMTimeInvalid, kCMTimeInvalid, kCMTimeInvalid};
        CMVideoFormatDescriptionRef videoInfo = NULL;
        OSStatus result = CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixelBuffer, &videoInfo);
        
        CMSampleBufferRef sampleBuffer = NULL;
        result = CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixelBuffer, true, NULL, NULL, videoInfo, &timing, &sampleBuffer);
        
        if (sampleBuffer == NULL) {
            return;
        }
        
        CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, YES);
        CFMutableDictionaryRef dict = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        CFDictionarySetValue(dict, kCMSampleAttachmentKey_DisplayImmediately, kCFBooleanTrue);
        
        // Get rendering layer
        AVSampleBufferDisplayLayer *displayLayer = GetSampleBufferDisplayLayer();
        
        // render sampleBuffer now
        if (@available(iOS 17.0, *)) {
            [displayLayer.sampleBufferRenderer enqueueSampleBuffer:sampleBuffer];
        } else {
            [displayLayer enqueueSampleBuffer:sampleBuffer];
        }

        // After become forground from background, may render fail
        if (displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
            [displayLayer flush];
            NSLog(@"Render failed, flush display layer");
        }
        
        CFRelease(videoInfo);
        CFRelease(sampleBuffer);
        
        sampleBuffer = NULL;
        dict = NULL;
    }
}

AVFrame * ScrcpyHandleFrame(AVFrame *frame) {
    if (!frame) {
        return frame;
    }
    
    // Get CVImageBufferRef
    CVPixelBufferRef pixelBuffer = (CVPixelBufferRef)frame->data[3];
    if (!pixelBuffer) {
        return frame;
    }
   
    if (ScrcpyEnableHardwareDecoding() == ScrcpyHardwareDecodingLayerRender) {
        RenderPixelBufferFrame(pixelBuffer);
        return frame;
    }
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    // Set frame format to YUV420P
    frame->format = AV_PIX_FMT_YUV420P;
    
    uint8_t* y_plane = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0);
    int y_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    
    uint8_t* uv_plane = (uint8_t*)CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1);
    int uv_stride = (int)CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    
    static uint8_t* u_plane = NULL;
    if (!u_plane) u_plane = (uint8_t*)malloc((frame->width * frame->height) / 4);
    static uint8_t* v_plane = NULL;
    if (!v_plane) v_plane = (uint8_t*)malloc((frame->width * frame->height) / 4);

    if (!u_plane || !v_plane) {
        if (u_plane) free(u_plane);
        if (v_plane) free(v_plane);
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return frame;
    }
    
    for (int i = 0; i < frame->height/2; i++) {
        for (int j = 0; j < frame->width/2; j++) {
            u_plane[i * (frame->width/2) + j] = uv_plane[i * uv_stride + j * 2];
            v_plane[i * (frame->width/2) + j] = uv_plane[i * uv_stride + j * 2 + 1];
        }
    }

    // Update to frame
    frame->data[0] = y_plane;
    frame->data[1] = u_plane;
    frame->data[2] = v_plane;
    frame->linesize[0] = y_stride;
    frame->linesize[1] = frame->width / 2;
    frame->linesize[2] = frame->width / 2;
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);

    // Release frame->data[3] to prevent memory leak
    frame->data[3] = NULL;

    return frame;
}
