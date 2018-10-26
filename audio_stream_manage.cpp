#include "audio_stream_manage.h"

#include <functional>

using namespace std::placeholders;

AudioStreamManage* AudioStreamManage::inst_=new AudioStreamManage();

AudioStreamManage* AudioStreamManage::GetInstance()
{
    return inst_;
}

AudioStreamManage::AudioStreamManage()
                  :packetBufferSize(0)
                  ,play_buffer_size_(0)
                  ,packetBuffer(nullptr)
                  ,play_buffer_(nullptr)
{
    //构造各个模块
    audio_device_.reset(AudioDevice::Create());
    audio_coding_factory_.reset(AudioCodingFactory::Create());
    record_pcm_quene_.reset(new AudioPacketQuene());
    aac_enc_quene_.reset(new AudioPacketQuene());
    play_pcm_quene_.reset(new AudioPacketQuene());
    aac_dec_quene_.reset(new AudioPacketQuene());
    av_transport_.reset(AVTransport::Create());

    audio_coding_factory_->Init();
    audio_encoder_.reset(audio_coding_factory_->CreateEncoder());
    audio_decoder_.reset(audio_coding_factory_->CreateDecoder());

    //初始模块
    audio_device_->Init(8000,1);
    audio_device_->InitPlayout(std::bind(&AudioStreamManage::OnSpeakerPlayCb,this,_1,_2,_3));
    audio_device_->InitRecording(std::bind(&AudioStreamManage::OnMicRecordCb,this,_1));
    audio_device_->SetLoudspeakerStatus(true);

    audio_encoder_->Init(8000,1,"AAC",
                         std::bind(&AudioStreamManage::OnEncoderInputCb,this,_1,_2,_3,_4),
                         std::bind(&AudioStreamManage::OnEncoderOutputCb,this,_1));

    audio_decoder_->Init(8000,1,"AAC",std::bind(&AudioStreamManage::OnDecoderInputCb,this,_1),
                                      std::bind(&AudioStreamManage::OnDecoderOutputCb,this,_1));

    av_transport_->Init(std::bind(&AudioStreamManage::OnAvTransportNeedAudioData,this,_1),
                        std::bind(&AudioStreamManage::OnAvTransportRecvAudioData,this,_1));
    
}

AudioStreamManage::~AudioStreamManage()
{   
    audio_encoder_->Destroy();
    audio_decoder_->Destroy();
    audio_coding_factory_->Destroy();
    audio_device_->Destory();

    if (nullptr != packetBuffer) {
        delete []  packetBuffer;
        packetBuffer=nullptr;
    }

    if (nullptr != play_buffer_) {
        delete []  play_buffer_;
        play_buffer_=nullptr;
    }
}

void AudioStreamManage::Start()
{   
    record_pcm_quene_->start();
    aac_enc_quene_->start();
    aac_dec_quene_->start();
    play_pcm_quene_->start();

    audio_device_->StartRecording();
    audio_device_->StartPlayout();
    audio_encoder_->Start();
    audio_decoder_->Start();
    av_transport_->Start("JWSX6TZZ2APRN3XG111A");
    
}

void AudioStreamManage::Stop()
{  
    record_pcm_quene_->stop();
    aac_enc_quene_->stop();
    aac_dec_quene_->stop();
    play_pcm_quene_->stop();

    audio_encoder_->Stop();
    audio_decoder_->Stop();
    audio_device_->StopRecording();
    audio_device_->StopPlayout();
    av_transport_->Stop();
    
}

void AudioStreamManage::SetDebugFileSavePath(std::string path)
{
    //for debug
    debug_save_path_=path;
    audio_encoder_->SetDebugFileSavePath(path);
}

void AudioStreamManage::OnMicRecordCb(AudioPacket* pkt)
{
    record_pcm_quene_->put(pkt);
    //printf("OnMicRecordCb:%d\r\n",pkt->size);
}

int AudioStreamManage::OnSpeakerPlayCb(int16_t *samples, int frame_size, int nb_channels)
{
    int needInshortSize = frame_size * nb_channels;
    int curCopyInshortSize = 0;
    AudioPacket* pkt;
    while (true) {
        if (play_buffer_size_ == 0) {
            int ret = play_pcm_quene_->get(&pkt,true);
            if (ret < 0) {
                return ret;
            }
            else
            {
               play_buffer_size_=pkt->size;
               if (nullptr == play_buffer_) {
                   play_buffer_ = new short[play_buffer_size_];
               }
               memcpy(play_buffer_, pkt->buffer, play_buffer_size_ * 2);
               if (nullptr != pkt) {
                   delete pkt;
                   pkt = nullptr;
               }
            }
        }

        if((curCopyInshortSize+play_buffer_size_)<=needInshortSize)
        {
           memcpy((samples+curCopyInshortSize),play_buffer_,play_buffer_size_*2);
           curCopyInshortSize+=play_buffer_size_;
           play_buffer_size_=0;
            if(curCopyInshortSize==needInshortSize)
                break;
            else
                continue;
        }
        else
        {
            int need=needInshortSize-curCopyInshortSize;
            memcpy((samples+curCopyInshortSize),play_buffer_,need*2);
            play_buffer_size_-=need;
            memmove(play_buffer_,play_buffer_+need,play_buffer_size_*2);
            break;
        }
    }
    return needInshortSize;
}

int  AudioStreamManage::OnEncoderInputCb(int16_t *samples, int frame_size, int nb_channels, double* presentationTimeMills)
{
    int needInshortSize = frame_size * nb_channels;
    int curCopyInshortSize = 0;
    AudioPacket* pkt;
    while (true) {
        if (packetBufferSize == 0) {
            int ret = record_pcm_quene_->get(&pkt,true);
            if (ret < 0) {
                return ret;
            }
            else
            {
               packetBufferSize=pkt->size;
               if (nullptr == packetBuffer) {
                   packetBuffer = new short[packetBufferSize];
               }
               memcpy(packetBuffer, pkt->buffer, packetBufferSize * 2);
                
               if (nullptr != pkt) {
                   delete pkt;
                   pkt = nullptr;
               }
            }
        }

        if((curCopyInshortSize+packetBufferSize)<=needInshortSize)
        {
           memcpy((samples+curCopyInshortSize),packetBuffer,packetBufferSize*2);
           curCopyInshortSize+=packetBufferSize;
           packetBufferSize=0;
            
            if(curCopyInshortSize==needInshortSize)
                break;
            else
                continue;
        }
        else
        {
            int need=needInshortSize-curCopyInshortSize;
            memcpy((samples+curCopyInshortSize),packetBuffer,need*2);
            packetBufferSize-=need;
            memmove(packetBuffer,packetBuffer+need,packetBufferSize*2);
            break;
        }
    }
        
    return needInshortSize;
}

int  AudioStreamManage::OnEncoderOutputCb(AudioPacket* audioPacket)
{
    aac_enc_quene_->put(audioPacket);
    //printf("OnEncoderOutputCb:%d\r\n",audioPacket->size);
    return 0;
}

int  AudioStreamManage::OnDecoderInputCb(AudioPacket** audioPacket)
{
    return aac_dec_quene_->get(audioPacket,true);
}

int  AudioStreamManage::OnDecoderOutputCb(AudioPacket* audioPacket)
{
    return play_pcm_quene_->put(audioPacket);
}

int  AudioStreamManage::OnAvTransportNeedAudioData(AudioPacket** audioPacket)
{
    return aac_enc_quene_->get(audioPacket,true);
}

int  AudioStreamManage::OnAvTransportRecvAudioData(AudioPacket* audioPacket)
{
    return aac_dec_quene_->put(audioPacket);;
}
