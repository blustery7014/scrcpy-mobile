//
//  ScrcpyMetalView.h
//  Scrcpy Remote
//
//  Created by Ethan on 5/23/25.
//

#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@interface ScrcpyMetalView : MTKView

/**
 * 渲染 CVPixelBufferRef
 * @param pixelBuffer 视频帧数据
 */
- (void)renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;

/**
 * 清空显示内容
 */
- (void)clear;

/**
 * 设置内容填充模式
 */
@property (nonatomic, assign) UIViewContentMode contentMode;

/**
 * 设置最大帧率（1-120 FPS）
 * 默认值：60 FPS
 */
@property (nonatomic, assign) NSInteger maxFrameRate;

/**
 * 获取当前渲染统计信息
 */
@property (nonatomic, readonly) BOOL isCurrentlyRendering;

/**
 * 强制刷新纹理缓存
 * 用于释放过多的纹理内存
 */
- (void)flushTextureCache;

/**
 * 获取当前视频尺寸
 */
@property (nonatomic, readonly) CGSize currentVideoSize;

@end

NS_ASSUME_NONNULL_END
