//
//  ScrcpyBlockWrapper.m
//  Scrcpy Remote
//
//  Created by Ethan on 12/15/24.
//

#import "ScrcpyBlockWrapper.h"

typedef struct {
    void *key;
    IMP blockIMP;
} ScrcpyBlockEntry;

#define ScrcpyBlockEntryMax 1024

IMP GetSet_ScrcpyBlockIMP(ScrcpyBlockEntry *entries, void *key, IMP blockIMP) {
    // Find entry by key
    ScrcpyBlockEntry *entry = NULL;
    int entryCount = 0;
    for (int i = 0; i < ScrcpyBlockEntryMax; i++) {
        if (entries[i].key == key) {
            entry = &entries[i];
        }
        if (entries[i].key) {
            entryCount++;
        }
    }

    // If entry exists, and blockIMP is nil, means retrieve IMP
    if (!blockIMP && entry) {
        return entry->blockIMP;
    }
        
    // If entry not exists, and blockIMP is nil, means not found
    if (!entry && !blockIMP) {
        return nil;
    }
    
    // If entry not exists, and blockIMP is not nil, means insert
    if (!entry && blockIMP) {
        // Insert at non-null entry
        if (entryCount >= ScrcpyBlockEntryMax) {
            // Empty all entries
            NSLog(@"ScrcpyBlockEntryMax: %d, entryCount: %d, empty all entries", ScrcpyBlockEntryMax, entryCount);
            for (int i = 0; i < ScrcpyBlockEntryMax; i++) {
                entries[i].key = NULL;
                entries[i].blockIMP = NULL;
            }
        }
        
        for (int i = 0; i < ScrcpyBlockEntryMax; i++) {
            if (!entries[i].key) {
                entries[i].key = key;
                entries[i].blockIMP = blockIMP;
                break;
            }
        }
    }
    
    // If entry exists, and blockIMP is not nil, means update
    if (entry && blockIMP) {
        entry->blockIMP = blockIMP;
        return blockIMP;
    }
    
    return nil;
}

/**
 * BlockEntry: GotFrameBufferUpdateBlock
 */

IMP GetSet_GotFrameBufferUpdateBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

void GotFrameBufferUpdateBlock(rfbClient* cl, int x, int y, int w, int h) {
    IMP blockIMP = GetSet_GotFrameBufferUpdateBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"GotFrameBufferUpdateBlock IMP not found for: %p", cl);
        return;
    }
    
    void (*block)(rfbClient* cl, void *, int x, int y, int w, int h) = (void (*)(rfbClient* cl, void *sel, int x, int y, int w, int h))blockIMP;
    block(cl, NULL, x, y, w, h);
}

/**
 * BlockEntry: GetCredentialBlock
 */

IMP GetSet_GetCredentialBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

rfbCredential *GetCredentialBlock(rfbClient* cl, int credentialType) {
    IMP blockIMP = GetSet_GetCredentialBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"GetCredentialBlock IMP not found for: %p", cl);
        return NULL;
    }
    
    rfbCredential *(*block)(rfbClient* cl, void *, int credentialType) = (rfbCredential *(*)(rfbClient* cl, void *sel, int credentialType))blockIMP;
    return block(cl, NULL, credentialType);
}

/**
 * BlockEntry: MallocFrameBufferBlock
 */

IMP GetSet_MallocFrameBufferBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

rfbBool MallocFrameBufferBlock(rfbClient* cl) {
    IMP blockIMP = GetSet_MallocFrameBufferBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"MallocFrameBufferBlock IMP not found for: %p", cl);
        return FALSE;
    }
    
    rfbBool (*block)(rfbClient* cl, void *) = (rfbBool (*)(rfbClient* cl, void *sel))blockIMP;
    return block(cl, NULL);
}

/**
 * BlockEntry: GotCursorShapeBlock
 */

IMP GetSet_GotCursorShapeBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

void GotCursorShapeBlock(rfbClient* cl, int xhot, int yhot, int width, int height, int bytesPerPixel) {
    IMP blockIMP = GetSet_GotCursorShapeBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"GotCursorShapeBlock IMP not found for: %p", cl);
        return;
    }
    
    void (*block)(rfbClient* cl, void *, int xhot, int yhot, int width, int height, int bytesPerPixel) = (void (*)(rfbClient* cl, void *sel, int xhot, int yhot, int width, int height, int bytesPerPixel))blockIMP;
    block(cl, NULL, xhot, yhot, width, height, bytesPerPixel);
}

/**
 * BlockEntry: HandleCursorPosBlock
 */

IMP GetSet_HandleCursorPosBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

rfbBool HandleCursorPosBlock(rfbClient* cl, int x, int y) {
    IMP blockIMP = GetSet_HandleCursorPosBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"HandleCursorPosBlock IMP not found for: %p", cl);
        return FALSE;
    }
    
    rfbBool (*block)(rfbClient* cl, void *, int x, int y) = (rfbBool (*)(rfbClient* cl, void *sel, int x, int y))blockIMP;
    return block(cl, NULL, x, y);
}

/**
 * BlockEntry: GetPasswordBlock
 */

IMP GetSet_GetPasswordBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

char *GetPasswordBlock(rfbClient* cl) {
    IMP blockIMP = GetSet_GetPasswordBlockIMP(cl, nil);
    if (!blockIMP) {
        NSLog(@"GetPasswordBlock IMP not found for: %p", cl);
        return NULL;
    }

    char *(*block)(rfbClient* cl, void *) = (char *(*)(rfbClient* cl, void *sel))blockIMP;
    return block(cl, NULL);
}

/**
 * BlockEntry: FinishedFrameBufferUpdateBlock
 */

IMP GetSet_FinishedFrameBufferUpdateBlockIMP(rfbClient* cl, IMP blockIMP) {
    static ScrcpyBlockEntry entries[ScrcpyBlockEntryMax] = {0};
    return GetSet_ScrcpyBlockIMP(entries, cl, blockIMP);
}

void FinishedFrameBufferUpdateBlock(rfbClient* cl) {
    IMP blockIMP = GetSet_FinishedFrameBufferUpdateBlockIMP(cl, nil);
    if (!blockIMP) {
        // 不输出日志，因为这个回调是可选的
        return;
    }

    void (*block)(rfbClient* cl, void *) = (void (*)(rfbClient* cl, void *sel))blockIMP;
    block(cl, NULL);
}
