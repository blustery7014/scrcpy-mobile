//
//  ScrcpyBlockWrapper.h
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import <Foundation/Foundation.h>
#import <rfb/rfbclient.h>

#ifndef ScrcpyBlockWrapper_h
#define ScrcpyBlockWrapper_h

IMP GetSet_GotFrameBufferUpdateBlockIMP(rfbClient* cl, IMP blockIMP);
void GotFrameBufferUpdateBlock(rfbClient* cl, int x, int y, int w, int h);

IMP GetSet_GetCredentialBlockIMP(rfbClient* cl, IMP blockIMP);
rfbCredential *GetCredentialBlock(rfbClient* cl, int credentialType);

IMP GetSet_MallocFrameBufferBlockIMP(rfbClient* cl, IMP blockIMP);
rfbBool MallocFrameBufferBlock(rfbClient* cl);

IMP GetSet_GotCursorShapeBlockIMP(rfbClient* cl, IMP blockIMP);
void GotCursorShapeBlock(rfbClient* cl, int xhot, int yhot, int width, int height, int bytesPerPixel);

IMP GetSet_HandleCursorPosBlockIMP(rfbClient* cl, IMP blockIMP);
rfbBool HandleCursorPosBlock(rfbClient* cl, int x, int y);

IMP GetSet_GetPasswordBlockIMP(rfbClient* cl, IMP blockIMP);
char *GetPasswordBlock(rfbClient* cl);

IMP GetSet_FinishedFrameBufferUpdateBlockIMP(rfbClient* cl, IMP blockIMP);
void FinishedFrameBufferUpdateBlock(rfbClient* cl);

#endif /* ScrcpyBlockWrapper_h */
