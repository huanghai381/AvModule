#ifndef AUDIO_ENCODER_FFMPEG_IMPL_H
#define AUDIO_ENCODER_FFMPEG_IMPL_H

#include <functional>
#include <pthread.h>
#include <string>

#include "media/platform_dependent/platform_4_live_ffmpeg.h"
#include "media/module/audio_coding/audio_encoder_interface.h"


class AudioEncoderFFmpegImpl : public AudioEncoderInterface
{
public:
    AudioEncoderFFmpegImpl();
    ~AudioEncoderFFmpegImpl();

    //override from AudioEncoderInterface
    int Init(int sampleRate, int channels, const char * codec_name,FillPcmFunc fill_pcm_func,EncFrameOutputFunc enc_frame_out_fuc) override;
    void Start() override;
    void Stop() override;
    void Destroy() override;
    void SetDebugFileSavePath(std::string path) override;

private:
    int Encode();
    int AllocAudioStream(const char * codec_name);
    int AllocAvframe();
    static void* EncodeThread(void* ptr);

private:
    AVCodecContext* avCodec_context_;
    AVFrame *		encode_frame_;
    int             sample_rate_;
    int             channels_;
    int       		audio_nb_samples_;
    uint8_t **		audio_samples_data_;
    int64_t 		audio_next_pts;
    FillPcmFunc fill_pcm_func_;
    EncFrameOutputFunc enc_frame_out_func_;
    
    /** 控制编码线程的状态量 **/
    bool 		is_encoding_;
    pthread_t encoder_thread_;
    //for debug
    std::string debug_file_save_path_;
    FILE* encoder_save_fd_; 
};

#endif // AUDIO_ENCODER_FFMPEG_IMPL_H
