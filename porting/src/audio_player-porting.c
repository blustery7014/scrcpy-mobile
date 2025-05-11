//
//  audio_player-porting.c
//  scrcpy-module
//
//  Created by Ethan on 2023/5/21.
//

#define sc_audio_regulator_pull(...)        sc_audio_regulator_pull_hijack(__VA_ARGS__)

#include "audio_player.c"

#undef sc_audio_regulator_pull

float ScrpyAudioVolumeScale(float update_scale);

void sc_audio_regulator_pull(struct sc_audio_regulator *ar, uint8_t *out,
                        uint32_t out_samples);
void sc_audio_regulator_pull_hijack(struct sc_audio_regulator *ar, uint8_t *out,
                        uint32_t out_samples) {
	sc_audio_regulator_pull(ar, out, out_samples);

	// Adjust volume
    float volume_scale = ScrpyAudioVolumeScale(0);
	printf("Adjusting volume by %f...\n", volume_scale);
    
    // 处理 AUDIO_F32 格式
    float *samples = (float *)out;

    // 计算样本数量 (假设是立体声，即2个通道)
    // 如果ar中有channels信息，可以使用ar->channels替代这里的2
    size_t channels = 2;
    size_t sample_count = out_samples * channels;

    for (size_t i = 0; i < sample_count; ++i) {
        samples[i] *= volume_scale;

        // 限制在浮点音频的正常范围内 (-1.0 到 1.0)
        if (samples[i] > 1.0f) samples[i] = 1.0f;
        if (samples[i] < -1.0f) samples[i] = -1.0f;
    }
}
