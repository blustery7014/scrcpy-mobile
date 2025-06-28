//
//  RenderRegionCalculator.m
//  VNCClient
//
//  Created by Ethan on 6/15/25.
//

#import "RenderRegionCalculator.h"
#import <UIKit/UIKit.h>


@implementation RenderRegionResult 
@end

@implementation RenderRegionCalculator

+ (RenderRegionResult *)calculateRenderRegionWithScreenSize:(CGSize)screenSize
                                                  imageSize:(CGSize)imageSize
                                                scaleFactor:(CGFloat)scaleFactor
                                                   centerX:(CGFloat)centerX
                                                   centerY:(CGFloat)centerY {
    
    RenderRegionResult *result = [[RenderRegionResult alloc] init];
    
    // 1. 计算图像在屏幕上的初始显示尺寸（保持宽高比）
    CGFloat screenRatio = screenSize.width / screenSize.height;
    CGFloat imageRatio = imageSize.width / imageSize.height;
    
    CGSize displaySize;
    if (imageRatio > screenRatio) {
        // 图像更宽，以屏幕宽度为准
        displaySize.width = screenSize.width;
        displaySize.height = screenSize.width / imageRatio;
    } else {
        // 图像更高，以屏幕高度为准
        displaySize.height = screenSize.height;
        displaySize.width = screenSize.height * imageRatio;
    }
    
    // 2. 应用缩放因子
    CGSize scaledSize = CGSizeMake(displaySize.width * scaleFactor,
                                   displaySize.height * scaleFactor);
    
    // 3. 计算缩放中心在屏幕上的实际坐标
    CGFloat centerScreenX = centerX * screenSize.width;
    CGFloat centerScreenY = centerY * screenSize.height;
    
    // 4. 计算缩放后图像在屏幕上的显示区域
    CGFloat displayLeft = centerScreenX - (centerScreenX - (screenSize.width - displaySize.width) / 2.0) * scaleFactor;
    CGFloat displayTop = centerScreenY - (centerScreenY - (screenSize.height - displaySize.height) / 2.0) * scaleFactor;
    CGFloat displayRight = displayLeft + scaledSize.width;
    CGFloat displayBottom = displayTop + scaledSize.height;
    
    // 5. 计算屏幕可见区域
    CGFloat visibleLeft = MAX(0, displayLeft);
    CGFloat visibleTop = MAX(0, displayTop);
    CGFloat visibleRight = MIN(screenSize.width, displayRight);
    CGFloat visibleBottom = MIN(screenSize.height, displayBottom);
    
    // 6. 将屏幕坐标转换为图像坐标
    CGRect sourceRect = CGRectZero;
    CGRect targetRect = CGRectZero;
    
    if (scaledSize.width > 0 && scaledSize.height > 0) {
        // 计算在缩放图像中的相对位置
        CGFloat relLeft = (visibleLeft - displayLeft) / scaledSize.width;
        CGFloat relTop = (visibleTop - displayTop) / scaledSize.height;
        CGFloat relRight = (visibleRight - displayLeft) / scaledSize.width;
        CGFloat relBottom = (visibleBottom - displayTop) / scaledSize.height;
        
        // 转换为原始图像坐标
        CGFloat srcLeft = relLeft * imageSize.width;
        CGFloat srcTop = relTop * imageSize.height;
        CGFloat srcRight = relRight * imageSize.width;
        CGFloat srcBottom = relBottom * imageSize.height;
        
        // 确保坐标在图像范围内
        srcLeft = MAX(0, MIN(imageSize.width, srcLeft));
        srcTop = MAX(0, MIN(imageSize.height, srcTop));
        srcRight = MAX(0, MIN(imageSize.width, srcRight));
        srcBottom = MAX(0, MIN(imageSize.height, srcBottom));
        
        sourceRect = CGRectMake(srcLeft, srcTop,
                               srcRight - srcLeft,
                               srcBottom - srcTop);
        
        targetRect = CGRectMake(visibleLeft, visibleTop,
                               visibleRight - visibleLeft,
                               visibleBottom - visibleTop);
    }
    
    // 设置结果
    result.sourceRect = sourceRect;
    result.targetRect = targetRect;
    result.displaySize = displaySize;
    result.scaledSize = scaledSize;
    result.scaleFactor = scaleFactor;
    
    return result;
}

@end

