//
//  audio_regulator-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2025/1/5.
//  Used for hihack sc_audiobuf_read to ajust volume
#include "audio_regulator.h"

float ScrcpyAudioVolumeScale(float volume_scale) {
    static float scale = 1.0;
    if (volume_scale > 0.0 && volume_scale <= 5.0) {
        scale = volume_scale;
    }
    return scale;
}

int swr_convert_hijack(struct SwrContext *s, uint8_t **out, int out_count,
                const uint8_t **in , int in_count) {
    int ret = swr_convert(s, out, out_count, in, in_count);
    
    // Adjust volume
//    float volume_scale = ScrcpyAudioVolumeScale(0.0);
//    if (volume_scale != 1.0) {
//        for (int i = 0; i < out_count; i++) {
//            uint16_t s = (uint16_t)((*out)[i] + 10);
//            (*out)[i] = (uint8_t)(s > 255 ? 255 : s);
//        }
//    }

    return ret;
}

#define swr_convert(...)        swr_convert_hijack(__VA_ARGS__)

#include "audio_regulator.c"

#undef swr_convert
