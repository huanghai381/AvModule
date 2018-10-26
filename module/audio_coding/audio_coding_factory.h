//
//  audio_encode_interface.hpp
//  ss181_app
//
//  Created by iisfree on 2018/9/22.
//  Copyright © 2018年 huanghai. All rights reserved.
//

#ifndef audio_coding_factory_h
#define audio_coding_factory_h

#include "audio_encoder_interface.h"
#include "audio_decoder_interface.h"

class AudioCodingFactory
{
public:
    static AudioCodingFactory* Create();
    virtual ~AudioCodingFactory(){}
    

    virtual int Init()=0;
    virtual AudioEncoderInterface* CreateEncoder()=0;
    virtual AudioDecoderInterface* CreateDecoder()=0;
    virtual void Destroy()=0;
    
};

#endif /* audio_coding_factory_h */
