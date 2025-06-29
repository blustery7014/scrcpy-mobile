//
//  ScrcpyVNCRuntime.h
//  VNCClient
//
//  Created by Ethan on 6/28/25.
//

#ifndef ScrcpyVNCRuntime_h
#define ScrcpyVNCRuntime_h

#import <Foundation/Foundation.h>
#import <SDL2/SDL.h>
#import <rfb/rfbclient.h>
#import "ScrcpyBlockWrapper.h"

@class ScrcpyVNCClient;

// VNC runtime callback setup functions

rfbBool VNCRuntimeMallocFrameBuffer(rfbClient* client, ScrcpyVNCClient *vncClient, SDL_Window **sdlWindow, SDL_Renderer **sdlRenderer, SDL_Texture **sdlTexture);

/**
 * 设置帧缓冲区更新回调
 */
void VNCRuntimeSetupGotFrameBufferUpdateCallback(rfbClient* client, SDL_Texture* sdlTexture, SDL_Renderer* sdlRenderer, SDL_Window* sdlWindow);

/**
 * 设置鼠标位置处理回调
 */
void VNCRuntimeSetupHandleCursorPosCallback(rfbClient* client, int* currentMouseX, int* currentMouseY);

/**
 * 设置密码获取回调
 */
void VNCRuntimeSetupGetPasswordCallback(rfbClient* client, NSString* password);

/**
 * 设置凭据获取回调
 */
void VNCRuntimeSetupGetCredentialCallback(rfbClient* client, NSString* user, NSString* password);

/**
 * 清理所有VNC回调
 */
void VNCRuntimeCleanupCallbacks(rfbClient* client);

/**
 * 绘制macOS风格的鼠标光标
 */
void VNCRuntimeDrawMacOSCursor(SDL_Renderer* renderer, int x, int y, float scale);

#endif /* ScrcpyVNCRuntime_h */
