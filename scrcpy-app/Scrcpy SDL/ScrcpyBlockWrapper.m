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
