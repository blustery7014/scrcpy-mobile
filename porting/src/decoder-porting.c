//
//  decoder-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/8.
//

#define avcodec_receive_frame(...)        avcodec_receive_frame_hijack(__VA_ARGS__)

#include "decoder.c"

#undef avcodec_receive_frame

int ScrcpyEnableHardwareDecoding(void);
int avcodec_receive_frame(AVCodecContext *avctx, AVFrame *frame);
AVFrame * ScrcpyHandleFrame(AVFrame *pending_frame);

int avcodec_receive_frame_hijack(AVCodecContext *avctx, AVFrame *frame) {
    int ret = avcodec_receive_frame(avctx, frame);

    if (ret == 0 && ScrcpyEnableHardwareDecoding() > 0) {
        // Fix Hardware Decoding Error After Return From Background
		ScrcpyHandleFrame(frame);
        return 0;
    }

    return ret;
}
