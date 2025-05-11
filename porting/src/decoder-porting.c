//
//  decoder-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2022/6/8.
//

#define avcodec_send_packet(...)        avcodec_send_packet_hijack(__VA_ARGS__)
#define avcodec_receive_frame(...)        avcodec_receive_frame_hijack(__VA_ARGS__)

#include "decoder.c"

#undef avcodec_receive_frame
#undef avcodec_send_packet

int ScrcpyEnableHardwareDecoding(void);
bool GetUpdateApplicationBackgroundState(bool update);
int avcodec_send_packet(AVCodecContext *avctx, const AVPacket *avpkt);
int avcodec_receive_frame(AVCodecContext *avctx, AVFrame *frame);
AVFrame * ScrcpyHandleFrame(AVFrame *pending_frame);

int avcodec_send_packet_hijack(AVCodecContext *avctx, const AVPacket *avpkt) {
    int ret = avcodec_send_packet(avctx, avpkt);
    return ret < 0 ? 0 : ret;
}

int avcodec_receive_frame_hijack(AVCodecContext *avctx, AVFrame *frame) {
    int ret = avcodec_receive_frame(avctx, frame);
    if (ret == 0 && ScrcpyEnableHardwareDecoding() > 0) {
		ScrcpyHandleFrame(frame);
        return 0;
    }
    return ret;
}
