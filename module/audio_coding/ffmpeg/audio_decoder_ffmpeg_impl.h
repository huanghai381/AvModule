#ifndef AUDIO_DECODER_FFMPEG_IMPL_H
#define AUDIO_DECODER_FFMPEG_IMPL_H

#include <functional>
#include <pthread.h>

#include "media/platform_dependent/platform_4_live_ffmpeg.h"
#include "media/module/audio_coding/audio_decoder_interface.h"

class AudioDecoderFFmpegImpl : public AudioDecoderInterface
{
public:
    AudioDecoderFFmpegImpl(); 
    ~AudioDecoderFFmpegImpl();

    //override from AudioDecoderInterface
    int Init(int sampleRate, int channels, const char * codec_name,FillEncFrameFunc fill_enc_frame_func,DecPcmOutputFunc dec_pcm_output_func) override;
    void Start() override;
    void Stop() override;
    void Destroy() override;
    void SetDebugFileSavePath(std::string path) override;


private:
    int Decode();

    static void* DecodeThread(void* ptr);

private:
    AVCodecContext* avCodec_context_;
    AVCodec *       codec_;
    AVFrame *		pcm_frame_;
    AVPacket        packet;

    //重采样
    SwrContext *swrContext;
    void *swrBuffer;
    int swrBufferSize;

    int             sample_rate_;
    int             channels_;
    FillEncFrameFunc fill_enc_frame_func_;
    DecPcmOutputFunc dec_pcm_output_func_;
    /** 控制解码线程的状态量 **/
    bool 		is_decoding_;
    pthread_t decoder_thread_;

};

#endif // AUDIO_DECODER_FFMPEG_IMPL_H
