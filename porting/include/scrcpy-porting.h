//
//  scrcpy.h
//  scrcpy-mobile
//
//  Created by Ethan on 2022/6/2.
//

#ifndef scrcpy_h
#define scrcpy_h

#include <stdio.h>
int scrcpy_main(int argc, char *argv[]);

enum ScrcpyStatus {
    ScrcpyStatusDisconnected = 0,
   	ScrcpyStatusADBConnected,
    ScrcpyStatusSDLInited,
    ScrcpyStatusSDLWindowCreated,
    ScrcpyStatusConnecting,
    ScrcpyStatusConnectingFailed,
    ScrcpyStatusConnected,
    ScrcpyStatusSDLWindowAppeared,
};
void ScrcpyUpdateStatus(enum ScrcpyStatus status);

// Custom audio volume adjust
float ScrcpyAudioVolumeScale(float volume_scale);

#endif /* scrcpy_h */
