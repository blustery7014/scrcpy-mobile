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

#endif /* ScrcpyBlockWrapper_h */
