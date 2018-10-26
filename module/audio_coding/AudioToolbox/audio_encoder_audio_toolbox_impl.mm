
#import "audio_encoder_audio_toolbox_impl.h"

const int PUBLISH_BITE_RATE=24000;
#define DEBUG_ENCODER_OUT_DATA  0


AudioEncoderAudioToolboxImpl::AudioEncoderAudioToolboxImpl()
                             :aacBuffer(nullptr)
                             ,pcmBuffer(nullptr)
{
    
}

AudioEncoderAudioToolboxImpl::~AudioEncoderAudioToolboxImpl()
{
    
}

int AudioEncoderAudioToolboxImpl::Init(int sampleRate, int channels, const char * codec_name,FillPcmFunc fill_pcm_func,EncFrameOutputFunc enc_frame_out_fuc)
{
    sample_rate_=sampleRate;
    channels_=channels;
    fill_pcm_func_=fill_pcm_func;
    enc_frame_out_func_=enc_frame_out_fuc;
    
    AllocAudioStream(codec_name);
    return 0;
}

void AudioEncoderAudioToolboxImpl::Start()
{
    if(DEBUG_ENCODER_OUT_DATA)
    {
        std::string m4a_path;
        m4a_path=debug_file_save_path_;
        m4a_path+="/encoder_aac.m4a";
        
        NSLog(@"encoder aac save path:%s",m4a_path.c_str());
        encoder_save_fd_=fopen(m4a_path.c_str(),"wb");
    }
    is_encoding_=true;
    pthread_create(&encoder_thread_, NULL, EncodeThread, this);
}

void AudioEncoderAudioToolboxImpl::Stop()
{
    if(DEBUG_ENCODER_OUT_DATA)
    {
        fclose(encoder_save_fd_);
        encoder_save_fd_=NULL;
    }
    
    is_encoding_=false;
    pthread_join(encoder_thread_, 0);
}

void AudioEncoderAudioToolboxImpl::Destroy()
{
    if(pcmBuffer) {
        free(pcmBuffer);
        pcmBuffer = NULL;
    }
    if(aacBuffer) {
        free(aacBuffer);
        aacBuffer = NULL;
    }
    AudioConverterDispose(audioConverter);
    NSLog(@"end destroy!!!");
}

void AudioEncoderAudioToolboxImpl::SetDebugFileSavePath(std::string path)
{
    debug_file_save_path_=path;
}

void AudioEncoderAudioToolboxImpl::AllocAudioStream(const char * codec_name)
{
    //构建InputABSD
    AudioStreamBasicDescription inAudioStreamBasicDescription = {0};
    UInt32 bytesPerSample = sizeof (SInt16);
    inAudioStreamBasicDescription.mFormatID = kAudioFormatLinearPCM;
    inAudioStreamBasicDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    inAudioStreamBasicDescription.mBytesPerPacket = bytesPerSample * channels_;
    inAudioStreamBasicDescription.mBytesPerFrame = bytesPerSample * channels_;
    inAudioStreamBasicDescription.mChannelsPerFrame = channels_;
    inAudioStreamBasicDescription.mFramesPerPacket = 1;
    inAudioStreamBasicDescription.mBitsPerChannel = 16;
    inAudioStreamBasicDescription.mSampleRate = sample_rate_;
    inAudioStreamBasicDescription.mReserved = 0;
    //构造OutputABSD
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    outAudioStreamBasicDescription.mSampleRate = inAudioStreamBasicDescription.mSampleRate;
    outAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC; // 设置编码格式
    outAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC; // 无损编码 ，0表示没有
    outAudioStreamBasicDescription.mBytesPerPacket = 0;
    outAudioStreamBasicDescription.mFramesPerPacket = 1024;
    outAudioStreamBasicDescription.mBytesPerFrame = 0;
    outAudioStreamBasicDescription.mChannelsPerFrame = inAudioStreamBasicDescription.mChannelsPerFrame;
    outAudioStreamBasicDescription.mBitsPerChannel = 0;
    outAudioStreamBasicDescription.mReserved = 0;
    //构造编码器类的描述
    AudioClassDescription *description =GetAudioClassDescriptionWithType(kAudioFormatMPEG4AAC,kAppleSoftwareAudioCodecManufacturer);//软编

    if(description==nil)
        NSLog(@"GetAudioClassDescriptionWithType failed!");
    
    //构建AudioConverter
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, description, &audioConverter);
    if (status != 0) {
        NSLog(@"setup converter: %d", (int)status);
    }
    UInt32 ulSize = sizeof(PUBLISH_BITE_RATE);
    status = AudioConverterSetProperty(audioConverter, kAudioConverterEncodeBitRate, ulSize, &PUBLISH_BITE_RATE);
    UInt32 size = sizeof(aacBufferSize);
    AudioConverterGetProperty(audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &aacBufferSize);
    NSLog(@"Expected BitRate is %@, Output PacketSize is %d", @(PUBLISH_BITE_RATE), aacBufferSize);
    //aacBufferSize = 1024;
    aacBuffer = (uint8_t*)malloc(aacBufferSize * sizeof(uint8_t));
    memset(aacBuffer, 0, aacBufferSize);
}

AudioClassDescription * AudioEncoderAudioToolboxImpl::GetAudioClassDescriptionWithType(int type,int manufacturer)
{
    static AudioClassDescription desc;
    
    UInt32 encoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders,
                                    sizeof(encoderSpecifier),
                                    &encoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Encoders,
                                sizeof(encoderSpecifier),
                                &encoderSpecifier,
                                &size,
                                descriptions);
    if (st) {
        NSLog(@"error getting audio format propery: %d", (int)(st));
        return nil;
    }
    
    for (unsigned int i = 0; i < count; i++) {
        if ((type == descriptions[i].mSubType) &&
            (manufacturer == descriptions[i].mManufacturer)) {
            memcpy(&desc, &(descriptions[i]), sizeof(desc));
            return &desc;
        }
    }
    
    return nil;
}

NSData* AudioEncoderAudioToolboxImpl::adtsDataForPacketLength(NSUInteger packetLength)
{
    int adtsLength = 7;
    char *packet = (char*)malloc(sizeof(char) * adtsLength);
    // Variables Recycled by addADTStoPacket
    int profile = 2;  //AAC LC
    //39=MediaCodecInfo.CodecProfileLevel.AACObjectELD;
    int freqIdx = 11;  //8KHz
    int chanCfg = channels_;  //MPEG-4 Audio Channel Configuration. 1 Channel front-center
    NSUInteger fullLength = adtsLength + packetLength;
    // fill in ADTS data
    packet[0] = (char)0xFF; // 11111111     = syncword
    packet[1] = (char)0xF9; // 1111 1 00 1  = syncword MPEG-2 Layer CRC
    packet[2] = (char)(((profile-1)<<6) + (freqIdx<<2) +(chanCfg>>2));
    packet[3] = (char)(((chanCfg&3)<<6) + (fullLength>>11));
    packet[4] = (char)((fullLength&0x7FF) >> 3);
    packet[5] = (char)(((fullLength&7)<<5) + 0x1F);
    packet[6] = (char)0xFC;
    NSData *data = [NSData dataWithBytesNoCopy:packet length:adtsLength freeWhenDone:YES];
    return data;
}

OSStatus AudioEncoderAudioToolboxImpl::fillAudioRawData(AudioBufferList * ioData ,UInt32 * ioNumberDataPackets)
{
    UInt32 requestedPackets = *ioNumberDataPackets;
    uint32_t bufferLength = requestedPackets * channels_ * 2;
    int actualFillSampleSize=0;
    double presentationTimeMills = -1;
    if(nullptr == pcmBuffer) {
        pcmBuffer = (uint8_t*)malloc(bufferLength);
    }
    
    /** 1、调用注册的回调方法来填充音频的PCM数据 **/
    actualFillSampleSize=fill_pcm_func_((int16_t *) pcmBuffer, requestedPackets, channels_, &presentationTimeMills);
    if (actualFillSampleSize <= 0) {
        *ioNumberDataPackets = 0;
        return -1;
    }
    ioData->mBuffers[0].mData = pcmBuffer;
    ioData->mBuffers[0].mDataByteSize = actualFillSampleSize*2;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = channels_;
    *ioNumberDataPackets = 1 ;
    
    return noErr;
}

OSStatus inInputDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioEncoderAudioToolboxImpl *encoder = (AudioEncoderAudioToolboxImpl *)(inUserData);
    return encoder->fillAudioRawData(ioData , ioNumberDataPackets);
}

void* AudioEncoderAudioToolboxImpl::EncodeThread(void* ptr)
{
@autoreleasepool {
    AudioEncoderAudioToolboxImpl* obj = (AudioEncoderAudioToolboxImpl *) ptr;
    obj->Encode();
    pthread_exit(0);
}
    return 0;
}

int AudioEncoderAudioToolboxImpl::Encode()
{
    char* data;
    NSUInteger len;
    while (is_encoding_) {
        if (audioConverter) {
            NSError *error = nil;
            AudioBufferList outAudioBufferList = {0};
            outAudioBufferList.mNumberBuffers = 1;
            outAudioBufferList.mBuffers[0].mNumberChannels = channels_;
            outAudioBufferList.mBuffers[0].mDataByteSize = (int)aacBufferSize;
            outAudioBufferList.mBuffers[0].mData = aacBuffer;
            AudioStreamPacketDescription *outPacketDescription = NULL;
            UInt32 ioOutputDataPacketSize = 1;
            // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
            // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
            OSStatus status = AudioConverterFillComplexBuffer(audioConverter, inInputDataProc, this, &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
            if (status == 0) {
                
                NSData *rawAAC = [NSData dataWithBytesNoCopy:outAudioBufferList.mBuffers[0].mData length:outAudioBufferList.mBuffers[0].mDataByteSize freeWhenDone:NO];
                NSData *adtsHeader = adtsDataForPacketLength(rawAAC.length);
                NSMutableData *fullData = [NSMutableData dataWithData:adtsHeader];
                [fullData appendData:rawAAC];
                
                //转换为我们的AudioPacket
                data=(char*)[fullData bytes];
                len=[fullData length] ;
                
                AudioPacket *audioPacket = new AudioPacket();
                audioPacket->data = new char[len];
                memcpy(audioPacket->data, data, len);
                audioPacket->size = (int)len;
                
                if(DEBUG_ENCODER_OUT_DATA)
                {
                    //NSLog(@"packet size:%d",audioPacket->size);
                    fwrite(audioPacket->data, 1, audioPacket->size, encoder_save_fd_);
                }
                
                enc_frame_out_func_(audioPacket);

            } else {
                error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
                NSLog(@"Converter Failed");
            }
            
        } else {
            NSLog(@"Audio Converter Init Failed...");
            break;
        }
    }
    
    return 0;
}
