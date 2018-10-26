#ifndef AUDIO_STREAM_MANAGE_H
#define AUDIO_STREAM_MANAGE_H

#include <memory>
#include <string>

#include "media/module/audio_device/audio_device.h"
#include "media/module/audio_coding/audio_coding_factory.h"
#include "media/module/common/audio_packet_quene.h"
#include "module/av_transport/av_transport.h"

class AudioStreamManage
{
public:
    static AudioStreamManage* GetInstance();
    ~AudioStreamManage();

    void Start();
    void Stop();
    void SetDebugFileSavePath(std::string path);

private:
    AudioStreamManage();

    void OnMicRecordCb(AudioPacket* pkt);
    int  OnSpeakerPlayCb(int16_t *samples, int frame_size, int nb_channels);
    int  OnEncoderInputCb(int16_t *samples, int frame_size, int nb_channels, double* presentationTimeMills);
    int  OnEncoderOutputCb(AudioPacket* audioPacket);
    int  OnDecoderInputCb(AudioPacket** audioPacket);
    int  OnDecoderOutputCb(AudioPacket* audioPacket);
    int  OnAvTransportNeedAudioData(AudioPacket** audioPacket);
    int  OnAvTransportRecvAudioData(AudioPacket* audioPacket);

private:
    static AudioStreamManage* inst_;

    std::unique_ptr<AudioDevice> audio_device_;
    std::unique_ptr<AudioCodingFactory> audio_coding_factory_;
    std::unique_ptr<AudioEncoderInterface> audio_encoder_;
    std::unique_ptr<AudioDecoderInterface> audio_decoder_;
    std::unique_ptr<AudioPacketQuene> record_pcm_quene_;
    std::unique_ptr<AudioPacketQuene> aac_enc_quene_;
    std::unique_ptr<AudioPacketQuene> play_pcm_quene_;
    std::unique_ptr<AudioPacketQuene> aac_dec_quene_;
    std::unique_ptr<AVTransport> av_transport_;

    /** 由于音频的buffer大小和每一帧的大小不一样，所以我们利用缓存数据的方式来 分次得到正确的音频数据 **/

    //采集音频缓存
    int 								packetBufferSize; //缓存buffer数据大小，short格式
    short* 								packetBuffer;  //缓存上一次取剩下的buffer数据

    //播放音频缓存
    int 								play_buffer_size_; //缓存buffer数据大小，short格式
    short* 								play_buffer_;  //缓存上一次取剩下的buffer数据
    
    
    //for debug
    std::string debug_save_path_;

};

#endif // AUDIO_STREAM_MANAGE_H
