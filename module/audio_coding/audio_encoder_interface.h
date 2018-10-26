//
//  audio_encoder_interface.h
//  ss181_app
//
//  Created by iisfree on 2018/9/22.
//  Copyright © 2018年 huanghai. All rights reserved.
//

#ifndef audio_encoder_interface_h
#define audio_encoder_interface_h

#include <functional>

#include "media/module/common/media_packet.h"

typedef std::function<int(int16_t *, int, int, double*)> FillPcmFunc;
typedef std::function<int(AudioPacket* audioPacket)> EncFrameOutputFunc;

class AudioEncoderInterface
{
public:
    virtual ~AudioEncoderInterface() {}

    virtual int Init(int sampleRate, int channels,const char * codec_name,FillPcmFunc fill_pcm_func,EncFrameOutputFunc enc_frame_out_fuc)=0;
    virtual void Start()=0;
    virtual void Stop()=0;
    virtual void SetDebugFileSavePath(std::string path)=0;
    virtual void Destroy()=0;

};

#endif /* audio_encoder_interface_h */
