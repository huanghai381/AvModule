#ifndef AUDIO_DECODER_AUDIO_TOOLBOX_IMPL_H
#define AUDIO_DECODER_AUDIO_TOOLBOX_IMPL_H

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <functional>
#include <pthread.h>
#include <string>

#include "media/module/audio_coding/audio_decoder_interface.h"

class AudioDecoderAudioToolboxImpl : public AudioDecoderInterface
{
public:
    AudioDecoderAudioToolboxImpl();
    ~AudioDecoderAudioToolboxImpl();
    
    //override from AudioDecoderInterface
    int Init(int sampleRate, int channels, const char * codec_name,FillEncFrameFunc fill_enc_frame_func,DecPcmOutputFunc dec_pcm_output_func) override;
    void Start() override;
    void Stop() override;
    void Destroy() override;
    void SetDebugFileSavePath(std::string path) override;
    
    OSStatus fillAudioEncData(AudioBufferList * ioData ,UInt32 * ioNumberDataPackets);
    
private:
    int Decode();
    void AllocAudioStream(const char * codec_name);
    AudioClassDescription * GetAudioClassDescriptionWithType(int type,int manufacturer);
    
    static void* DecodeThread(void* ptr);
    
private:
    int             sample_rate_;
    int             channels_;

    DecPcmOutputFunc dec_pcm_output_func_;
    FillEncFrameFunc fill_enc_frame_func_;
    
    uint8_t*               aacBuffer;
    UInt32                 aacBufferSize;
    uint8_t*               pcmBuffer;
    UInt32                 pcmBufferSize;
    AudioConverterRef      audioConverter;
    /** 控制编码线程的状态量 **/
    bool         is_decoding_;
    pthread_t    decoder_thread_;
    //for debug
    std::string debug_file_save_path_;
};

#endif  //AUDIO_DECODER_AUDIO_TOOLBOX_IMPL_H
