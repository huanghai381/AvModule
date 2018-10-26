#ifndef AUDIO_CODING_FACTORY_FFMPEG_IMPL_H
#define AUDIO_CODING_FACTORY_FFMPEG_IMPL_H

#include "media/module/audio_coding/audio_coding_factory.h"

extern "C" {
    #include "libavcodec/avcodec.h"
    #include "libavformat/avformat.h"
    #include "libavutil/avutil.h"
    #include "libavutil/samplefmt.h"
    #include "libavutil/common.h"
    #include "libavutil/channel_layout.h"
    #include "libavutil/opt.h"
    #include "libavutil/imgutils.h"
    #include "libavutil/mathematics.h"
};

class AudioCodingFactoryFFmpegImpl : public AudioCodingFactory
{
public:
    AudioCodingFactoryFFmpegImpl();
    ~AudioCodingFactoryFFmpegImpl();

    //override from AudioCodingInterface
    int Init() override;
    AudioEncoderInterface* CreateEncoder() override;
    AudioDecoderInterface* CreateDecoder() override;
    void Destroy() override;
};

#endif // AUDIO_CODING_FACTORY_FFMPEG_IMPL_H
