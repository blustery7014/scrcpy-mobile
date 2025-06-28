//
//  ScrcpyVNCClient+MouseControl.m
//  VNCClient
//
//  Created by Ethan on 12/28/24.
//

#import "ScrcpyVNCClient+MouseControl.h"
#import "ScrcpyVNCClient+Private.h"
#import <QuartzCore/QuartzCore.h>
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>

@implementation ScrcpyVNCClient (MouseControl)

#pragma mark - Mouse Event Methods

- (void)sendMouseClickAtLocation:(CGPoint)location isRightClick:(BOOL)isRightClick {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    CGPoint vncLocation = [self convertSDLToVNCCoordinate:location];
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    int clickButtonMask = isRightClick ? rfbButton3Mask : rfbButton1Mask;
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Sending %@ click at SDL(%.1f, %.1f) -> VNC(%d, %d)", 
          isRightClick ? @"right" : @"left", location.x, location.y, vncX, vncY);
    
    // 首先发送鼠标移动到点击位置（确保光标在正确位置）
    rfbBool result = SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to move to click position");
        return;
    }
    usleep(5000); // 5ms延迟
    
    // 发送按下事件（添加点击按钮到当前按钮状态）
    int pressButtonMask = self.buttonMask | clickButtonMask;
    result = SendPointerEvent(self.rfbClient, vncX, vncY, pressButtonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send button press event");
        return;
    }
    usleep(20000); // 20ms延迟（模拟真实点击时间）
    
    // 发送释放事件（移除点击按钮，保持其他按钮状态）
    result = SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send button release event");
        return;
    }
    
    NSLog(@"✅ [ScrcpyVNCClient] %@ click completed at VNC(%d, %d)",
          isRightClick ? @"Right" : @"Left", vncX, vncY);
}

- (void)sendMouseMoveToLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    // location 参数已经是 CursorPosManager 计算好的远程坐标
    CGPoint vncLocation = location;
    
    int vncX = (int)round(vncLocation.x);
    int vncY = (int)round(vncLocation.y);
    
    // 边界检查
    vncX = MAX(0, MIN(self.imagePixelsSize.width - 1, vncX));
    vncY = MAX(0, MIN(self.imagePixelsSize.height - 1, vncY));
    
    // 简化日志输出，只在debug模式下显示
    #ifdef DEBUG
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastLogTime > 0.5) { // 每0.5秒记录一次
        NSLog(@"🖱️ [ScrcpyVNCClient] Mouse move to SDL(%.1f, %.1f) -> VNC(%d, %d)", 
              location.x, location.y, vncX, vncY);
        lastLogTime = currentTime;
    }
    #endif
    
    // 发送指针事件，保持当前按钮状态
    rfbBool result = SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send mouse move event");
        return;
    }
}

- (void)sendMouseDragStartAtLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Starting mouse drag at SDL(%.1f, %.1f)", location.x, location.y);
    
    // CursorPosManager 已在通知处理中管理拖拽状态，这里只需要发送VNC事件
    NSLog(@"✅ [ScrcpyVNCClient] Drag started at (%.1f, %.1f)", location.x, location.y);
}

- (void)sendMouseDragToLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    // location 参数已经是 CursorPosManager 计算好的远程坐标
    int vncX = (int)round(location.x);
    int vncY = (int)round(location.y);
    
    // 简化日志输出
    #ifdef DEBUG
    static NSTimeInterval lastDragLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastDragLogTime > 0.2) { // 每0.2秒记录一次
        NSLog(@"🖱️ [ScrcpyVNCClient] Dragging to VNC(%d, %d)", vncX, vncY);
        lastDragLogTime = currentTime;
    }
    #endif
    
    // 发送鼠标指针移动事件
    rfbBool result = SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send drag move event");
        return;
    }
    NSLog(@"✅ [ScrcpyVNCClient] Mouse drag moved to VNC(%d, %d)", vncX, vncY);
}

- (void)sendMouseDragEndAtLocation:(CGPoint)location {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Ending mouse drag at VNC(%.1f, %.1f)", location.x, location.y);
    
    // location 参数已经是 CursorPosManager 计算好的远程坐标，直接发送
    int vncX = (int)round(location.x);
    int vncY = (int)round(location.y);
    
    // 发送最终位置
    rfbBool result = SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask);
    if (!result) {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to send drag end event");
        return;
    }
    
    NSLog(@"✅ [ScrcpyVNCClient] Mouse drag completed at VNC(%d, %d)", vncX, vncY);
}

- (void)sendMouseWheelAtLocation:(CGPoint)location deltaX:(int)deltaX deltaY:(int)deltaY {
    if (![self isValidForMouseEvents]) {
        return;
    }
    
    // location 参数已经是 CursorPosManager 提供的远程坐标
    int vncX = (int)round(location.x);
    int vncY = (int)round(location.y);
    
    NSLog(@"🖱️ [ScrcpyVNCClient] Sending mouse wheel at VNC(%d, %d), delta: (%d, %d)", 
          vncX, vncY, deltaX, deltaY);
    
    // VNC滚轮事件通过按钮4和5实现（向上和向下滚动）
    rfbBool result;
    if (deltaY > 0) {
        // 向上滚动 - 使用临时按钮状态
        int wheelButtonMask = self.buttonMask | rfbButton4Mask;
        result = SendPointerEvent(self.rfbClient, vncX, vncY, wheelButtonMask);
        if (result) {
            usleep(10000); // 10ms延迟
            SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask); // 恢复原按钮状态
        }
    } else if (deltaY < 0) {
        // 向下滚动 - 使用临时按钮状态
        int wheelButtonMask = self.buttonMask | rfbButton5Mask;
        result = SendPointerEvent(self.rfbClient, vncX, vncY, wheelButtonMask);
        if (result) {
            usleep(10000); // 10ms延迟
            SendPointerEvent(self.rfbClient, vncX, vncY, self.buttonMask); // 恢复原按钮状态
        }
    }
    
    // 处理水平滚动（如果支持）
    if (deltaX != 0) {
        // 水平滚动可以通过按钮6和7实现（如果服务端支持）
        NSLog(@"🖱️ [ScrcpyVNCClient] Horizontal scroll detected, deltaX: %d (not implemented)", deltaX);
    }
}

#pragma mark - Cursor Management

- (void)requestCursorUpdate {
    if (!self.rfbClient || !self.connected) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Cannot request cursor update: not connected");
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"🖱️ [ScrcpyVNCClient] Manually requesting cursor update");
        
        // 发送帧缓冲更新请求，这可能触发光标形状更新
        SendFramebufferUpdateRequest(self.rfbClient, 0, 0, self.rfbClient->width, self.rfbClient->height, TRUE);
        
        // 获取当前光标位置，如果没有就使用屏幕中心
        int currentX = self.cursorX > 0 ? self.cursorX : self.rfbClient->width / 2;
        int currentY = self.cursorY > 0 ? self.cursorY : self.rfbClient->height / 2;
        
        // 发送指针事件来触发光标位置和形状更新
        SendPointerEvent(self.rfbClient, currentX, currentY, 0);
        
        // 稍微移动一下光标位置再移回来，这可能会触发光标更新
        if (currentX > 0 && currentY > 0) {
            SendPointerEvent(self.rfbClient, currentX + 1, currentY, 0);
            usleep(10000); // 10ms delay
            SendPointerEvent(self.rfbClient, currentX, currentY, 0);
        }
        
        NSLog(@"🖱️ [ScrcpyVNCClient] Cursor update request sent");
    });
}

- (void)createDefaultArrowCursor {
    if (!self.currentRenderer) {
        NSLog(@"❌ [ScrcpyVNCClient] No renderer available for creating default cursor");
        return;
    }
    
    // 清理现有光标纹理
    if (self.cursorTexture) {
        SDL_DestroyTexture(self.cursorTexture);
        self.cursorTexture = NULL;
    }
    
    // 定义macOS风格的箭头光标 (19x19)
    self.cursorWidth = 19;
    self.cursorHeight = 19;
    self.cursorHotX = 1;
    self.cursorHotY = 1;
    
    // 创建macOS风格的黑色箭头光标数据（带白色边框）
    Uint32 arrowData[19 * 19];
    memset(arrowData, 0, sizeof(arrowData)); // 初始化为透明
    
    // 定义颜色
    Uint32 black = 0xFF000000;      // 黑色不透明 (ABGR格式)
    Uint32 white = 0xFFFFFFFF;      // 白色不透明
    Uint32 transparent = 0x00000000; // 透明
    
    // macOS风格箭头光标的像素图案
    // 使用二维数组定义光标形状：0=透明, 1=白色边框, 2=黑色填充
    int cursorPattern[19][19] = {
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,2,2,2,2,1,0,0,0,0,0,0,0},
        {0,1,2,2,2,2,2,1,1,1,1,1,0,0,0,0,0,0,0},
        {0,1,2,2,2,1,2,2,1,0,0,0,0,0,0,0,0,0,0},
        {0,1,2,2,1,0,1,2,2,1,0,0,0,0,0,0,0,0,0},
        {0,1,2,1,0,0,1,2,2,1,0,0,0,0,0,0,0,0,0},
        {0,1,1,0,0,0,0,1,2,2,1,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,1,2,2,1,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,1,1,0,0,0,0,0,0,0,0,0},
        {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    };
    
    // 根据图案填充像素数据
    for (int y = 0; y < 19; y++) {
        for (int x = 0; x < 19; x++) {
            int index = y * 19 + x;
            switch (cursorPattern[y][x]) {
                case 0:
                    arrowData[index] = transparent;
                    break;
                case 1:
                    arrowData[index] = white;
                    break;
                case 2:
                    arrowData[index] = black;
                    break;
            }
        }
    }
    
    // 创建纹理
    self.cursorTexture = SDL_CreateTexture(self.currentRenderer, SDL_PIXELFORMAT_RGBA8888,
                                          SDL_TEXTUREACCESS_STATIC, self.cursorWidth, self.cursorHeight);
    
    if (self.cursorTexture) {
        SDL_SetTextureBlendMode(self.cursorTexture, SDL_BLENDMODE_BLEND);
        
        int result = SDL_UpdateTexture(self.cursorTexture, NULL, arrowData, self.cursorWidth * sizeof(Uint32));
        
        if (result == 0) {
            self.cursorVisible = YES;
            NSLog(@"✅ [ScrcpyVNCClient] Default arrow cursor texture created successfully");
        } else {
            NSLog(@"❌ [ScrcpyVNCClient] Failed to update default cursor texture: %s", SDL_GetError());
            SDL_DestroyTexture(self.cursorTexture);
            self.cursorTexture = NULL;
        }
    } else {
        NSLog(@"❌ [ScrcpyVNCClient] Failed to create default cursor texture: %s", SDL_GetError());
    }
}

- (void)renderCursor {
    if (!self.cursorVisible || !self.cursorTexture || !self.currentRenderer) {
        return;
    }
    
    // 计算光标在屏幕上的位置（考虑缩放和偏移）
    int screenX = self.cursorX;
    int screenY = self.cursorY;
    
    // 应用渲染区域转换
    if (self.currentRenderingRegion) {
        CGFloat scaleX = self.currentRenderingRegion.targetRect.size.width / self.currentRenderingRegion.sourceRect.size.width;
        CGFloat scaleY = self.currentRenderingRegion.targetRect.size.height / self.currentRenderingRegion.sourceRect.size.height;
        
        screenX = (self.cursorX - self.currentRenderingRegion.sourceRect.origin.x) * scaleX + self.currentRenderingRegion.targetRect.origin.x;
        screenY = (self.cursorY - self.currentRenderingRegion.sourceRect.origin.y) * scaleY + self.currentRenderingRegion.targetRect.origin.y;
        
        // 应用热点偏移
        screenX -= self.cursorHotX * scaleX;
        screenY -= self.cursorHotY * scaleY;
        
        // 计算缩放后的光标尺寸
        int scaledWidth = self.cursorWidth * scaleX;
        int scaledHeight = self.cursorHeight * scaleY;
        
        // 设置渲染矩形
        SDL_Rect cursorRect = {screenX, screenY, scaledWidth, scaledHeight};
        
        // 渲染光标
        SDL_RenderCopy(self.currentRenderer, self.cursorTexture, NULL, &cursorRect);
    } else {
        // 没有渲染区域信息时使用原始尺寸
        screenX -= self.cursorHotX;
        screenY -= self.cursorHotY;
        
        SDL_Rect cursorRect = {screenX, screenY, self.cursorWidth, self.cursorHeight};
        SDL_RenderCopy(self.currentRenderer, self.cursorTexture, NULL, &cursorRect);
    }
}

#pragma mark - Touchpad Integration

- (void)handleTouchEvent:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event eventType:(NSString *)eventType {
    UITouch *primaryTouch = [touches anyObject];
    CGPoint location = [primaryTouch locationInView:primaryTouch.view];
    
    // Convert to local screen coordinates
    if (!CGSizeEqualToSize(self.cursorPosManager.localScreenSize, CGSizeZero)) {
        CGSize viewSize = primaryTouch.view.bounds.size;
        location.x = (location.x / viewSize.width) * self.cursorPosManager.localScreenSize.width;
        location.y = (location.y / viewSize.height) * self.cursorPosManager.localScreenSize.height;
    }
    
    if ([eventType isEqualToString:@"began"]) {
        if (touches.count == 1) {
            [self.cursorPosManager handleTouchBegin:location];
        }
    } else if ([eventType isEqualToString:@"moved"]) {
        if (touches.count == 1) {
            [self.cursorPosManager handleTouchMove:location];
        } else if (touches.count == 2) {
            // Handle two-finger scroll
            NSArray<UITouch *> *touchArray = [touches allObjects];
            UITouch *touch1 = touchArray[0];
            UITouch *touch2 = touchArray[1];
            
            CGPoint location1 = [touch1 locationInView:touch1.view];
            CGPoint location2 = [touch2 locationInView:touch2.view];
            CGPoint previousLocation1 = [touch1 previousLocationInView:touch1.view];
            CGPoint previousLocation2 = [touch2 previousLocationInView:touch2.view];
            
            // Calculate scroll delta based on average movement
            CGFloat deltaX = ((location1.x + location2.x) / 2.0) - ((previousLocation1.x + previousLocation2.x) / 2.0);
            CGFloat deltaY = ((location1.y + location2.y) / 2.0) - ((previousLocation1.y + previousLocation2.y) / 2.0);
            
            CGPoint centerLocation = CGPointMake((location1.x + location2.x) / 2.0, (location1.y + location2.y) / 2.0);
            
            // Convert to local coordinates
            if (!CGSizeEqualToSize(self.cursorPosManager.localScreenSize, CGSizeZero)) {
                CGSize viewSize = touch1.view.bounds.size;
                centerLocation.x = (centerLocation.x / viewSize.width) * self.cursorPosManager.localScreenSize.width;
                centerLocation.y = (centerLocation.y / viewSize.height) * self.cursorPosManager.localScreenSize.height;
                deltaX = (deltaX / viewSize.width) * self.cursorPosManager.localScreenSize.width;
                deltaY = (deltaY / viewSize.height) * self.cursorPosManager.localScreenSize.height;
            }
            
            [self.cursorPosManager handleScroll:centerLocation deltaX:deltaX deltaY:deltaY];
        }
    } else if ([eventType isEqualToString:@"ended"]) {
        if (touches.count == 1) {
            [self.cursorPosManager handleTouchEnd:location];
        } else if (touches.count == 2) {
            // Two-finger tap (right click)
            [self.cursorPosManager handleTwoFingerTap:location];
        }
    }
}

#pragma mark - CursorPosManagerDelegate

- (void)cursorPosManager:(CursorPosManager *)manager didGenerateEvent:(TouchpadEventType)eventType atRemoteLocation:(CGPoint)remoteLocation {
    if (!self.rfbClient || !self.connected) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Cannot process touchpad event: not connected");
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        switch (eventType) {
            case TouchpadEventTypeTap:
                NSLog(@"🖱️ [ScrcpyVNCClient] Processing tap at remote: (%.1f, %.1f)", remoteLocation.x, remoteLocation.y);
                [self sendMouseClickAtLocation:remoteLocation isRightClick:NO];
                break;
                
            case TouchpadEventTypeTwoFingerTap:
                NSLog(@"🖱️ [ScrcpyVNCClient] Processing two-finger tap (right click) at remote: (%.1f, %.1f)", remoteLocation.x, remoteLocation.y);
                [self sendMouseClickAtLocation:remoteLocation isRightClick:YES];
                break;
                
            case TouchpadEventTypeDragStart:
                NSLog(@"🖱️ [ScrcpyVNCClient] Processing drag start at remote: (%.1f, %.1f)", remoteLocation.x, remoteLocation.y);
                [self sendMouseDragStartAtLocation:remoteLocation];
                break;
                
            case TouchpadEventTypeDrag:
                [self sendMouseDragToLocation:remoteLocation];
                break;
                
            case TouchpadEventTypeDragEnd:
                NSLog(@"🖱️ [ScrcpyVNCClient] Processing drag end at remote: (%.1f, %.1f)", remoteLocation.x, remoteLocation.y);
                [self sendMouseDragEndAtLocation:remoteLocation];
                break;
                
            case TouchpadEventTypeMove:
                [self sendMouseMoveToLocation:remoteLocation];
                break;
                
            default:
                NSLog(@"⚠️ [ScrcpyVNCClient] Unknown touchpad event type: %ld", (long)eventType);
                break;
        }
    });
}

- (void)cursorPosManager:(CursorPosManager *)manager didGenerateScrollEvent:(CGPoint)remoteLocation deltaX:(CGFloat)deltaX deltaY:(CGFloat)deltaY {
    if (!self.rfbClient || !self.connected) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Cannot process scroll event: not connected");
        return;
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"🖱️ [ScrcpyVNCClient] Processing scroll at remote: (%.1f, %.1f) delta: (%.1f, %.1f)", 
              remoteLocation.x, remoteLocation.y, deltaX, deltaY);
        
        // Convert scroll deltas to wheel events
        // VNC wheel events use discrete steps, so we need to convert continuous deltas
        int wheelDeltaX = (int)round(deltaX / 10.0); // Scale down for reasonable scroll speed
        int wheelDeltaY = (int)round(deltaY / 10.0);
        
        if (wheelDeltaX != 0 || wheelDeltaY != 0) {
            [self sendMouseWheelAtLocation:remoteLocation deltaX:wheelDeltaX deltaY:wheelDeltaY];
        }
    });
}

- (void)cursorPosManager:(CursorPosManager *)manager didUpdateCursorPosition:(CGPoint)remoteLocation {
    if (!self.rfbClient || !self.connected) {
        return;
    }
    
    // Update the VNC cursor position for display
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cursorX = (int)remoteLocation.x;
        self.cursorY = (int)remoteLocation.y;
    });
    
    // Send cursor movement to server
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self sendMouseMoveToLocation:remoteLocation];
    });
}

#pragma mark - Internal Helper Methods

- (CGPoint)convertRemoteLocationToRenderRegion:(CGPoint)remoteLocation {
    if (!self.currentRenderingRegion) {
        return remoteLocation;
    }
    
    CGFloat scaleX = self.currentRenderingRegion.targetRect.size.width / self.currentRenderingRegion.sourceRect.size.width;
    CGFloat scaleY = self.currentRenderingRegion.targetRect.size.height / self.currentRenderingRegion.sourceRect.size.height;
    
    CGFloat renderX = (remoteLocation.x - self.currentRenderingRegion.sourceRect.origin.x) * scaleX + self.currentRenderingRegion.targetRect.origin.x;
    CGFloat renderY = (remoteLocation.y - self.currentRenderingRegion.sourceRect.origin.y) * scaleY + self.currentRenderingRegion.targetRect.origin.y;
    
    return CGPointMake(renderX, renderY);
}

- (CGPoint)convertRenderLocationToRemote:(CGPoint)renderLocation {
    if (!self.currentRenderingRegion) {
        return renderLocation;
    }
    
    CGFloat scaleX = self.currentRenderingRegion.sourceRect.size.width / self.currentRenderingRegion.targetRect.size.width;
    CGFloat scaleY = self.currentRenderingRegion.sourceRect.size.height / self.currentRenderingRegion.targetRect.size.height;
    
    CGFloat remoteX = (renderLocation.x - self.currentRenderingRegion.targetRect.origin.x) * scaleX + self.currentRenderingRegion.sourceRect.origin.x;
    CGFloat remoteY = (renderLocation.y - self.currentRenderingRegion.targetRect.origin.y) * scaleY + self.currentRenderingRegion.sourceRect.origin.y;
    
    return CGPointMake(remoteX, remoteY);
}

- (BOOL)isValidForMouseEvents {
    if (!self.rfbClient || !self.connected) {
        NSLog(@"⚠️ [ScrcpyVNCClient] VNC client not connected");
        return NO;
    }
    
    if (self.imagePixelsSize.width <= 0 || self.imagePixelsSize.height <= 0) {
        NSLog(@"⚠️ [ScrcpyVNCClient] Invalid image size: %.0fx%.0f", 
              self.imagePixelsSize.width, self.imagePixelsSize.height);
        return NO;
    }
    
    return YES;
}

- (CGPoint)convertSDLToVNCCoordinate:(CGPoint)sdlLocation {
    CGFloat vncX = sdlLocation.x;
    CGFloat vncY = sdlLocation.y;
    
    // 添加调试信息
    NSLog(@"🔍 [ConvertCoordinate] Input SDL(%.1f,%.1f), imageSize(%.0fx%.0f), renderingRegion: %@", 
          sdlLocation.x, sdlLocation.y, self.imagePixelsSize.width, self.imagePixelsSize.height, 
          self.currentRenderingRegion ? @"YES" : @"NO");
    
    // 如果有渲染区域信息，需要转换坐标
    if (self.currentRenderingRegion) {
        // 将SDL坐标转换为VNC坐标
        CGFloat scaleX = self.currentRenderingRegion.sourceRect.size.width / self.currentRenderingRegion.targetRect.size.width;
        CGFloat scaleY = self.currentRenderingRegion.sourceRect.size.height / self.currentRenderingRegion.targetRect.size.height;
        
        vncX = (sdlLocation.x - self.currentRenderingRegion.targetRect.origin.x) * scaleX + self.currentRenderingRegion.sourceRect.origin.x;
        vncY = (sdlLocation.y - self.currentRenderingRegion.targetRect.origin.y) * scaleY + self.currentRenderingRegion.sourceRect.origin.y;
        
        NSLog(@"🔍 [ConvertCoordinate] With RenderingRegion -> VNC(%.1f,%.1f)", vncX, vncY);
    }
    
    return CGPointMake(vncX, vncY);
}

@end
