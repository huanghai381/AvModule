#ifndef AUDIO_DECODER_INTERFACE_H
#define AUDIO_DECODER_INTERFACE_H

#include <functional>

#include "media/module/common/media_packet.h"

typedef std::function<int(AudioPacket** audioPacket)> FillEncFrameFunc;
typedef std::function<int(AudioPacket* audioPacket)>  DecPcmOutputFunc;

class AudioDecoderInterface
{
public:
    virtual ~AudioDecoderInterface() {}

    virtual int Init(int sampleRate, int channels, const char * codec_name,FillEncFrameFunc fill_enc_frame_func,DecPcmOutputFunc dec_pcm_output_func)=0;
    virtual void Start()=0;
    virtual void Stop()=0;
    virtual void Destroy()=0;
    virtual void SetDebugFileSavePath(std::string path)=0;

};



#endif // AUDIO_DECODER_INTERFACE_H
