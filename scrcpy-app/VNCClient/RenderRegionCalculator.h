//
//  RenderRegionCalculator.h
//  VNCClient
//
//  Created by Ethan on 6/15/25.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RenderRegionResult : NSObject
@property (nonatomic, assign) CGRect sourceRect;
@property (nonatomic, assign) CGRect targetRect;
@property (nonatomic, assign) CGSize displaySize;
@property (nonatomic, assign) CGSize scaledSize;
@property (nonatomic, assign) CGFloat scaleFactor;
@end

@interface RenderRegionCalculator : NSObject

+ (RenderRegionResult *)calculateRenderRegionWithScreenSize:(CGSize)screenSize
                                                  imageSize:(CGSize)imageSize
                                                scaleFactor:(CGFloat)scaleFactor
                                                    centerX:(CGFloat)centerX
                                                    centerY:(CGFloat)centerY;
@end

NS_ASSUME_NONNULL_END
