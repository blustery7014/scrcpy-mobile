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
void ScrcpyUpdateStatus(enum ScrcpyStatus status, const char *message);

// Custom audio volume adjust
float ScrcpyAudioVolumeScale(float volume_scale);

// Get process last output
const char *
scrcpy_process_get_last_output();

#endif /* scrcpy_h */
