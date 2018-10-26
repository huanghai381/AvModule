#include "audio_coding_factory_ffmpeg_impl.h"

#include "audio_decoder_ffmpeg_impl.h"
#include "audio_encoder_ffmpeg_impl.h"
#include "media/module/audio_coding/AudioToolbox/audio_encoder_audio_toolbox_impl.h"
#include "media/module/audio_coding/AudioToolbox/audio_decoder_audio_toolbox_impl.h"


AudioCodingFactory* AudioCodingFactory::Create()
{
    return new  AudioCodingFactoryFFmpegImpl();
}

AudioCodingFactoryFFmpegImpl::AudioCodingFactoryFFmpegImpl()
{
    av_register_all();
}

AudioCodingFactoryFFmpegImpl::~AudioCodingFactoryFFmpegImpl()
{

}

int AudioCodingFactoryFFmpegImpl::Init()
{
    return 0;
}

AudioEncoderInterface* AudioCodingFactoryFFmpegImpl::CreateEncoder()
{
    //return new AudioEncoderFFmpegImpl();
    return new AudioEncoderAudioToolboxImpl();
}

AudioDecoderInterface* AudioCodingFactoryFFmpegImpl::CreateDecoder()
{
    return new AudioDecoderFFmpegImpl();
    //return new AudioDecoderAudioToolboxImpl();
}

void AudioCodingFactoryFFmpegImpl::Destroy()
{

}
