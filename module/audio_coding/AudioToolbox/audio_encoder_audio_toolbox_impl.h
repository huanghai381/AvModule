#ifndef AUDIO_ENCODER_AUDIO_TOOLBOX_IMPL_H
#define AUDIO_ENCODER_AUDIO_TOOLBOX_IMPL_H

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <functional>
#include <pthread.h>
#include <string>

#include "media/platform_dependent/platform_4_live_ffmpeg.h"
#include "media/module/audio_coding/audio_encoder_interface.h"

class AudioEncoderAudioToolboxImpl : public AudioEncoderInterface
{
public:
    AudioEncoderAudioToolboxImpl();
    ~AudioEncoderAudioToolboxImpl();
    
    //override from AudioEncoderInterface
    int Init(int sampleRate, int channels, const char * codec_name,FillPcmFunc fill_pcm_func,EncFrameOutputFunc enc_frame_out_fuc) override;
    void Start() override;
    void Stop() override;
    void Destroy() override;
    void SetDebugFileSavePath(std::string path) override;
    
    OSStatus fillAudioRawData(AudioBufferList * ioData ,UInt32 * ioNumberDataPackets);
    
private:
    int Encode();
    void AllocAudioStream(const char * codec_name);
    AudioClassDescription * GetAudioClassDescriptionWithType(int type,int manufacturer);
    NSData* adtsDataForPacketLength(NSUInteger packetLength);
    
    static void* EncodeThread(void* ptr);
    
private:
    int             sample_rate_;
    int             channels_;

    FillPcmFunc fill_pcm_func_;
    EncFrameOutputFunc enc_frame_out_func_;
    
    uint8_t*               aacBuffer;
    UInt32                 aacBufferSize;
    uint8_t*               pcmBuffer;
    AudioConverterRef      audioConverter;
    /** 控制编码线程的状态量 **/
    bool         is_encoding_;
    pthread_t encoder_thread_;
    //for debug
    std::string debug_file_save_path_;
    FILE* encoder_save_fd_;
};

#endif  //AUDIO_ENCODER_AUDIO_TOOLBOX_IMPL_H
