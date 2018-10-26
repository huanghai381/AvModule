#ifndef audio_device_h
#define audio_device_h

#include <functional>

#include "media/module/common/media_packet.h"

typedef std::function<void(AudioPacket*)>  PcmRecordCb;
typedef std::function<int(int16_t *, int, int)> PcmPlayCb;

class AudioDevice
{
public:
    static AudioDevice* Create();
    virtual ~AudioDevice(){}

    //全局初始化，采集和播放设置同一采样率与通道
    virtual void Init(int sample_rate,int channel)=0;
    //初始播放
    virtual void InitPlayout(PcmPlayCb pcm_play_cb)=0;
    //初始mic
    virtual void InitRecording(PcmRecordCb pcm_record_cb)=0;
    
    //播放控制
    virtual int32_t StartPlayout()=0;
    virtual int32_t StopPlayout()=0;
    
    //mic采集控制
    virtual int32_t StartRecording()=0;
    virtual int32_t StopRecording()=0;
    
    virtual int32_t SetLoudspeakerStatus(bool enable)=0;

    virtual void Destory()=0;

};

#endif
