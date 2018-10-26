#include "audio_decoder_ffmpeg_impl.h"

#include <assert.h>

#include "media/platform_dependent/platform_4_live_common.h"

#define LOG_TAG "AudioDecoderFFmpegImpl"

AudioDecoderFFmpegImpl::AudioDecoderFFmpegImpl()
    :fill_enc_frame_func_(nullptr)
    ,dec_pcm_output_func_(nullptr)
    ,swrBuffer(nullptr)
{

}

AudioDecoderFFmpegImpl::~AudioDecoderFFmpegImpl()
{

}

int AudioDecoderFFmpegImpl::Init(int sampleRate, int channels, const char * codec_name,FillEncFrameFunc fill_enc_frame_func,DecPcmOutputFunc dec_pcm_output_func)
{
    sample_rate_=sampleRate;
    channels_=channels;
    fill_enc_frame_func_=fill_enc_frame_func;
    dec_pcm_output_func_=dec_pcm_output_func;

    if(codec_name!="AAC")
    {
        LOGI("only support aac decode!!");
        return -1;
    }

    codec_=avcodec_find_decoder(AV_CODEC_ID_AAC);

    if (codec_ == nullptr) {
        LOGI("Unsupported codec ");
        return -1;
    }

    avCodec_context_ = avcodec_alloc_context3(codec_);

    // 初始化codecCtx
    avCodec_context_->codec_type = AVMEDIA_TYPE_AUDIO;
    avCodec_context_->sample_rate = sampleRate;
    avCodec_context_->channels = channels;
    avCodec_context_->channel_layout = channels_ == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;

    // 打开codec
    int ret=avcodec_open2(avCodec_context_, codec_, NULL);
    if (ret >= 0) {
        LOGI("sucess avcodec_open2!");
    }
    else
    {
        LOGI("fail avcodec_open2 result!");
        return -1;
    }

    //判断是否需要重采样
    if(avCodec_context_->sample_fmt != AV_SAMPLE_FMT_S16)
    {
        swrContext = swr_alloc_set_opts(NULL, av_get_default_channel_layout(1), AV_SAMPLE_FMT_S16, avCodec_context_->sample_rate,
                                        av_get_default_channel_layout(avCodec_context_->channels), avCodec_context_->sample_fmt, avCodec_context_->sample_rate, 0, NULL);
        if (!swrContext || swr_init(swrContext)) {
            if (swrContext)
                swr_free(&swrContext);
            avcodec_close(avCodec_context_);
            av_free(avCodec_context_);
            LOGI("init resampler failed...");
            return -1;
        }
    }

    pcm_frame_ = avcodec_alloc_frame();
    return 1;
}

void AudioDecoderFFmpegImpl::Start()
{
    is_decoding_=true;
    pthread_create(&decoder_thread_, NULL, DecodeThread, this);
}

void AudioDecoderFFmpegImpl::Stop()
{
    is_decoding_=false;
    pthread_join(decoder_thread_, 0);
}

void AudioDecoderFFmpegImpl::Destroy()
{
    if(nullptr !=avCodec_context_) {
        avcodec_close(avCodec_context_);
        av_free(avCodec_context_);
        avCodec_context_ = nullptr;
    }

    if(nullptr !=pcm_frame_) {
        avcodec_free_frame(&pcm_frame_);
        pcm_frame_ = nullptr;
    }

    if (nullptr != swrBuffer) {
        free(swrBuffer);
        swrBuffer = nullptr;
        swrBufferSize = 0;
    }
    if (nullptr != swrContext) {
        swr_free(&swrContext);
        swrContext = nullptr;
    }
}


void AudioDecoderFFmpegImpl::SetDebugFileSavePath(std::string path)
{
    
}

int AudioDecoderFFmpegImpl::Decode()
{
    assert(fill_enc_frame_func_!=nullptr);
    assert(dec_pcm_output_func_!=nullptr);
    av_init_packet(&packet);

    AudioPacket* pkt;
    int gotframe = 0;
    int ret=1;
    while(is_decoding_)
    {
        ret=fill_enc_frame_func_(&pkt);
        if(ret<0)  //abort
        {
            break;
        }
        else if(ret==0)  //non block
        {
            continue;
        }
        else
        {
            packet.data = (uint8_t *)pkt->data;
            packet.size = pkt->size;

            int len = avcodec_decode_audio4(avCodec_context_, pcm_frame_,
                                            &gotframe, &packet);
            if (len < 0) {
                LOGI("decode audio error, skip packet");
            }
            if (gotframe) {
                int numChannels = 1;
                int numFrames = 0;
                void * audioData;
                if (swrContext) {
                    const int ratio = 2;
                    const int bufSize = av_samples_get_buffer_size(NULL,
                                                                   numChannels, pcm_frame_->nb_samples,
                                                                   AV_SAMPLE_FMT_S16, 1);
                    
                    if(!swrBuffer)
                    {
                        swrBufferSize = bufSize;
                        swrBuffer = malloc(swrBufferSize);
                    }
                    else if(swrBufferSize < bufSize)
                    {
                        swrBufferSize = bufSize;
                        swrBuffer = realloc(swrBuffer, swrBufferSize);
                    }
                    byte *outbuf[2] = { (byte*) swrBuffer, NULL };
                    numFrames = swr_convert(swrContext, outbuf,
                                            swrBufferSize,
                                            (const uint8_t **) pcm_frame_->data,
                                            pcm_frame_->nb_samples);

                    if (numFrames < 0) {
                        LOGI("fail resample audio");
                        continue;
                    }
                    audioData = swrBuffer;
                }
                else {
                    if (avCodec_context_->sample_fmt != AV_SAMPLE_FMT_S16) {
                        LOGI("bucheck, audio format is invalid");
                        ret = -1;
                        break;
                    }

                    audioData = pcm_frame_->data[0];
                    numFrames = pcm_frame_->nb_samples;
                }

                //输出解码数据
                AudioPacket* pcmPkt=new AudioPacket();
                pcmPkt->buffer=new short[numFrames];
                pcmPkt->size=numFrames;
                memcpy(pcmPkt->buffer,audioData,numFrames*2);
                dec_pcm_output_func_(pcmPkt);
            }
            else{
                LOGI("aac dec frame failed!");
            }
        }
    }
    av_free_packet(&packet);
    return ret;
}

void* AudioDecoderFFmpegImpl::DecodeThread(void* ptr)
{
    AudioDecoderFFmpegImpl* obj = (AudioDecoderFFmpegImpl *) ptr;
    obj->Decode();
    pthread_exit(0);
    return 0;
}
