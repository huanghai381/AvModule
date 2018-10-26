
#import "audio_decoder_audio_toolbox_impl.h"

#define DEBUG_DECODER_OUT_DATA  0


AudioDecoderAudioToolboxImpl::AudioDecoderAudioToolboxImpl()
                             :aacBuffer(nullptr)
                             ,pcmBuffer(nullptr)
{
    
}

AudioDecoderAudioToolboxImpl::~AudioDecoderAudioToolboxImpl()
{
    
}

int AudioDecoderAudioToolboxImpl::Init(int sampleRate, int channels, const char * codec_name,FillEncFrameFunc fill_enc_frame_func,DecPcmOutputFunc dec_pcm_output_func)
{
    sample_rate_=sampleRate;
    channels_=channels;
    fill_enc_frame_func_=fill_enc_frame_func;
    dec_pcm_output_func_=dec_pcm_output_func;
    
    AllocAudioStream(codec_name);
    return 0;
}

void AudioDecoderAudioToolboxImpl::Start()
{
    is_decoding_=true;
    pthread_create(&decoder_thread_, NULL, DecodeThread, this);
}

void AudioDecoderAudioToolboxImpl::Stop()
{
    is_decoding_=false;
    pthread_join(decoder_thread_, 0);
}

void AudioDecoderAudioToolboxImpl::Destroy()
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

void AudioDecoderAudioToolboxImpl::SetDebugFileSavePath(std::string path)
{
    debug_file_save_path_=path;
}

void AudioDecoderAudioToolboxImpl::AllocAudioStream(const char * codec_name)
{
    //构建InputABSD
    AudioStreamBasicDescription inAudioStreamBasicDescription = {0};
    inAudioStreamBasicDescription.mFormatID = kAudioFormatMPEG4AAC;
    inAudioStreamBasicDescription.mFormatFlags = kMPEG4Object_AAC_LC;
    inAudioStreamBasicDescription.mBytesPerPacket = 0;
    inAudioStreamBasicDescription.mBytesPerFrame = 0;
    inAudioStreamBasicDescription.mChannelsPerFrame = channels_;
    inAudioStreamBasicDescription.mFramesPerPacket = 1024;
    inAudioStreamBasicDescription.mBitsPerChannel = 0;
    inAudioStreamBasicDescription.mSampleRate = sample_rate_;
    inAudioStreamBasicDescription.mReserved = 0;
    //构造OutputABSD
    UInt32 bytesPerSample = sizeof (SInt16);
    AudioStreamBasicDescription outAudioStreamBasicDescription = {0};
    outAudioStreamBasicDescription.mSampleRate = sample_rate_;
    outAudioStreamBasicDescription.mFormatID = kAudioFormatLinearPCM; // 设置编码格式
    outAudioStreamBasicDescription.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    outAudioStreamBasicDescription.mBytesPerPacket = 2;
    outAudioStreamBasicDescription.mFramesPerPacket = 1;
    outAudioStreamBasicDescription.mBytesPerFrame = 2;
    outAudioStreamBasicDescription.mChannelsPerFrame = channels_;
    outAudioStreamBasicDescription.mBitsPerChannel = 16;
    outAudioStreamBasicDescription.mReserved = 0;
    
    //构造编码器类的描述
//    AudioClassDescription *description =GetAudioClassDescriptionWithType(kAudioFormatLinearPCM,kAppleSoftwareAudioCodecManufacturer);//软编
//
//    if(description==nil)
//        NSLog(@"AudioDecoderAudioToolboxImpl##GetAudioClassDescriptionWithType failed!");
    
    AudioClassDescription description;
    description.mType=kAudioDecoderComponentType;
    description.mSubType=kAudioFormatMPEG4AAC;
    description.mManufacturer=kAppleSoftwareAudioCodecManufacturer;
    
    //构建AudioConverter
    OSStatus status = AudioConverterNewSpecific(&inAudioStreamBasicDescription, &outAudioStreamBasicDescription, 1, &description, &audioConverter);
    if (status != 0) {
        NSLog(@"AudioDecoderAudioToolboxImpl##setup converter: %d", (int)status);
    }

    UInt32 size = sizeof(pcmBufferSize);
    AudioConverterGetProperty(audioConverter, kAudioConverterPropertyMaximumOutputPacketSize, &size, &pcmBufferSize);
    //NSLog(@"Output PacketSize is %d",pcmBufferSize);
    //aacBufferSize = 1024;
    pcmBufferSize=2048;
    pcmBuffer = (uint8_t*)malloc(pcmBufferSize);
    memset(pcmBuffer, 0, pcmBufferSize);
}

AudioClassDescription * AudioDecoderAudioToolboxImpl::GetAudioClassDescriptionWithType(int type,int manufacturer)
{
    static AudioClassDescription desc;
    
    UInt32 decoderSpecifier = type;
    OSStatus st;
    
    UInt32 size;
    st = AudioFormatGetPropertyInfo(kAudioFormatProperty_Decoders,
                                    sizeof(decoderSpecifier),
                                    &decoderSpecifier,
                                    &size);
    if (st) {
        NSLog(@"error getting audio format propery info: %d", (int)(st));
        return nil;
    }
    
    unsigned int count = size / sizeof(AudioClassDescription);
    AudioClassDescription descriptions[count];
    st = AudioFormatGetProperty(kAudioFormatProperty_Decoders,
                                sizeof(decoderSpecifier),
                                &decoderSpecifier,
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


OSStatus AudioDecoderAudioToolboxImpl::fillAudioEncData(AudioBufferList * ioData ,UInt32 * ioNumberDataPackets)
{
    UInt32 requestedPackets = *ioNumberDataPackets;
    uint32_t bufferLength = requestedPackets * channels_;
    int ret;
    if(nullptr == aacBuffer) {
        aacBuffer = (uint8_t*)malloc(bufferLength);
    }
    
    /** 1、调用注册的回调方法来填充音频的PCM数据 **/
    AudioPacket* pkt=nullptr;
    ret=fill_enc_frame_func_(&pkt);
    if ((ret <= 0)||pkt==nullptr) {
        *ioNumberDataPackets = 0;
        return -1;
    }
    
    aacBufferSize=pkt->size;
    memcpy(aacBuffer, pkt->data, aacBufferSize);
    delete pkt;
    pkt = nullptr;

    ioData->mBuffers[0].mData = aacBuffer;
    ioData->mBuffers[0].mDataByteSize = aacBufferSize;
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mNumberChannels = channels_;
    *ioNumberDataPackets = 1 ;
    
    return noErr;
}

OSStatus InputEncDataProc(AudioConverterRef inAudioConverter, UInt32 *ioNumberDataPackets, AudioBufferList *ioData, AudioStreamPacketDescription **outDataPacketDescription, void *inUserData)
{
    AudioDecoderAudioToolboxImpl *encoder = (AudioDecoderAudioToolboxImpl *)(inUserData);
    return encoder->fillAudioEncData(ioData , ioNumberDataPackets);
}

void* AudioDecoderAudioToolboxImpl::DecodeThread(void* ptr)
{
@autoreleasepool {
    AudioDecoderAudioToolboxImpl* obj = (AudioDecoderAudioToolboxImpl *) ptr;
    obj->Decode();
    pthread_exit(0);
}
    return 0;
}

int AudioDecoderAudioToolboxImpl::Decode()
{
    while (is_decoding_) {
        if (audioConverter) {
            NSError *error = nil;
            AudioBufferList outAudioBufferList = {0};
            outAudioBufferList.mNumberBuffers = 1;
            outAudioBufferList.mBuffers[0].mNumberChannels = channels_;
            outAudioBufferList.mBuffers[0].mDataByteSize = (int)pcmBufferSize;
            outAudioBufferList.mBuffers[0].mData = pcmBuffer;
            AudioStreamPacketDescription *outPacketDescription = NULL;
            UInt32 ioOutputDataPacketSize = 1;
            // Converts data supplied by an input callback function, supporting non-interleaved and packetized formats.
            // Produces a buffer list of output data from an AudioConverter. The supplied input callback function is called whenever necessary.
            OSStatus status = AudioConverterFillComplexBuffer(audioConverter, InputEncDataProc, this, &ioOutputDataPacketSize, &outAudioBufferList, outPacketDescription);
            if (status == 0) {

                //转换为我们的AudioPacket
                int pcmSize=outAudioBufferList.mBuffers[0].mDataByteSize;
                AudioPacket *audioPacket = new AudioPacket();
                audioPacket->buffer = new short[pcmSize/2];
                memcpy(audioPacket->buffer, outAudioBufferList.mBuffers[0].mData, pcmSize);
                audioPacket->size = pcmSize/2;
                dec_pcm_output_func_(audioPacket);
                NSLog(@"out pcm size:%d",audioPacket->size);
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
