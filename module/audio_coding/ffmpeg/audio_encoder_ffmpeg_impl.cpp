#include "audio_encoder_ffmpeg_impl.h"

#include <assert.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

#include "media/module/common/common_utils.h"
#include "media/platform_dependent/platform_4_live_common.h"


#ifndef PUBLISH_BITE_RATE
#define PUBLISH_BITE_RATE 24000
#endif

#define LOG_TAG "AudioEncoderFFmpegImpl"
#define DEBUG_ENCODER_OUT_DATA  0

AudioEncoderFFmpegImpl::AudioEncoderFFmpegImpl()
                       :fill_pcm_func_(nullptr)
                       ,enc_frame_out_func_(nullptr)
                       ,encoder_save_fd_(NULL)
{

}

AudioEncoderFFmpegImpl::~AudioEncoderFFmpegImpl()
{

}

int AudioEncoderFFmpegImpl::Init(int sampleRate, int channels, const char * codec_name,FillPcmFunc fill_pcm_func,EncFrameOutputFunc enc_frame_out_fuc)
{
    sample_rate_=sampleRate;
    channels_=channels;
    fill_pcm_func_=fill_pcm_func;
    enc_frame_out_func_=enc_frame_out_fuc;

    audio_next_pts=0.0;
    AllocAudioStream(codec_name);
    AllocAvframe();
    return 0;
}

void AudioEncoderFFmpegImpl::Start()
{
    if(DEBUG_ENCODER_OUT_DATA)
    {
        debug_file_save_path_+="/encoder.m4a";
        LOGI("encoder aac save path:%s",debug_file_save_path_.c_str());
        encoder_save_fd_=fopen(debug_file_save_path_.c_str(),"wb");
    }
    is_encoding_=true;
    pthread_create(&encoder_thread_, NULL, EncodeThread, this);
}

void AudioEncoderFFmpegImpl::Stop()
{
    if(DEBUG_ENCODER_OUT_DATA)
    {
        fclose(encoder_save_fd_);
        encoder_save_fd_=NULL;
    }
    
    is_encoding_=false;
    pthread_join(encoder_thread_, 0);
}

void AudioEncoderFFmpegImpl::Destroy()
{
    LOGI("start destroy!!!");
    if (nullptr != audio_samples_data_[0]) {
        av_free(audio_samples_data_[0]);
    }
    if (nullptr != encode_frame_) {
        av_free(encode_frame_);
    }
    if (nullptr != avCodec_context_) {
        avcodec_close(avCodec_context_);
        av_free(avCodec_context_);
    }
    LOGI("end destroy!!!");
}

void AudioEncoderFFmpegImpl::SetDebugFileSavePath(std::string path)
{
    debug_file_save_path_=path;
}

int AudioEncoderFFmpegImpl::Encode()
{
    assert(fill_pcm_func_!=nullptr);
    assert(enc_frame_out_func_!=nullptr);
    double presentationTimeMills = -1;
    int actualFillSampleSize=0;

    while (is_encoding_) {
        /** 1、调用注册的回调方法来填充音频的PCM数据 **/
        actualFillSampleSize=fill_pcm_func_((int16_t *) audio_samples_data_[0], audio_nb_samples_, channels_, &presentationTimeMills);
        if (actualFillSampleSize == -1) {
            LOGI("fillPCMFrameCallback failed return actualFillSampleSize is %d \n", actualFillSampleSize);
            break;
        }
        if (actualFillSampleSize == 0) {
            break;
        }
        
        int actualFillFrameNum = actualFillSampleSize / channels_;
        int audioSamplesSize = actualFillSampleSize * channels_ * sizeof(short);
        /** 2、将PCM数据按照编码器的格式编码到一个AVPacket中 **/
        AVRational time_base = {1, sample_rate_};
        int ret;
        AVPacket pkt = { 0 };
        int got_packet;
        av_init_packet(&pkt);
        pkt.duration = (int) AV_NOPTS_VALUE;
        pkt.pts = pkt.dts = 0;
        encode_frame_->nb_samples = actualFillFrameNum;
        avcodec_fill_audio_frame(encode_frame_, avCodec_context_->channels, avCodec_context_->sample_fmt, (const uint8_t *)audio_samples_data_[0], audioSamplesSize, 0);
        encode_frame_->pts = audio_next_pts;
        audio_next_pts += encode_frame_->nb_samples;
        ret = avcodec_encode_audio2(avCodec_context_, &pkt, encode_frame_, &got_packet);
        if (ret < 0 || !got_packet) {
            LOGI("Error encoding audio frame: %s\n", av_err2str(ret));
            av_free_packet(&pkt);
            continue;
        }
        if (got_packet) {
            
            pkt.pts = av_rescale_q(encode_frame_->pts, avCodec_context_->time_base, time_base);
            //转换为我们的AudioPacket
            AudioPacket *audioPacket = new AudioPacket();
            audioPacket->data = new char[pkt.size+7]; //加7字节ADTS头
            add8K1ChannelAacAdtsHeard(audioPacket->data,pkt.size);
            memcpy(audioPacket->data+7, pkt.data, pkt.size);
            audioPacket->size = pkt.size+7;
            audioPacket->position = (float)(pkt.pts * av_q2d(time_base) * 1000.0f);
            enc_frame_out_func_(audioPacket);
            
            if(DEBUG_ENCODER_OUT_DATA)
            {
                fwrite(audioPacket->data, 1, audioPacket->size, encoder_save_fd_);
            }
        }
        av_free_packet(&pkt);
    }
    
    return 0;
}

int AudioEncoderFFmpegImpl::AllocAudioStream(const char * codec_name)
{
    if(codec_name!="AAC")
    {
        LOGI("only support aac encode!!");
        return -1;
    }
    
    AVCodec *codec = avcodec_find_encoder_by_name("libfdk_aac");
    //AVCodec *codec = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!codec) {
        LOGI("Couldn't find a valid audio codec By Codec Name %s", codec_name);
        return -1;
    }
    avCodec_context_ = avcodec_alloc_context3(codec);
    avCodec_context_->codec_type = AVMEDIA_TYPE_AUDIO;
    avCodec_context_->sample_rate = sample_rate_;
    avCodec_context_->bit_rate = PUBLISH_BITE_RATE;
    avCodec_context_->sample_fmt = AV_SAMPLE_FMT_S16;
    LOGI("audioChannels is %d", channels_);
    LOGI("AV_SAMPLE_FMT_S16 is %d", AV_SAMPLE_FMT_S16);
    avCodec_context_->channel_layout = channels_ == 1 ? AV_CH_LAYOUT_MONO : AV_CH_LAYOUT_STEREO;
    avCodec_context_->channels = av_get_channel_layout_nb_channels(avCodec_context_->channel_layout);
    avCodec_context_->profile = FF_PROFILE_AAC_LOW;
    LOGI("avCodecContext->channels is %d", avCodec_context_->channels);
    avCodec_context_->flags |= CODEC_FLAG_GLOBAL_HEADER;
    avCodec_context_->codec_id = codec->id;
    if (avcodec_open2(avCodec_context_, codec, NULL) < 0) {
        LOGI("Couldn't open codec");
        return -2;
    }
    
    return 0;
}

int AudioEncoderFFmpegImpl::AllocAvframe()
{
    int ret = 0;
    encode_frame_ = avcodec_alloc_frame();
    if (!encode_frame_) {
        LOGI("Could not allocate audio frame\n");
        return -1;
    }
    encode_frame_->nb_samples = avCodec_context_->frame_size;
    encode_frame_->format = avCodec_context_->sample_fmt;
    encode_frame_->channel_layout = avCodec_context_->channel_layout;
    encode_frame_->sample_rate = avCodec_context_->sample_rate;

    audio_nb_samples_ = avCodec_context_->frame_size;
    //audio_nb_samples_ = avCodec_context_->codec->capabilities & CODEC_CAP_VARIABLE_FRAME_SIZE ? 10240 : avCodec_context_->frame_size;
    LOGI("AudioEncoderFFmpegImpl audio_nb_samples_:%d",audio_nb_samples_);
    int src_samples_linesize;
    ret = av_samples_alloc_array_and_samples(&audio_samples_data_, &src_samples_linesize, avCodec_context_->channels, audio_nb_samples_, avCodec_context_->sample_fmt, 0);
    if (ret < 0) {
        LOGI("Could not allocate source samples\n");
        return -1;
    }
    return ret;
}

void* AudioEncoderFFmpegImpl::EncodeThread(void* ptr)
{
    AudioEncoderFFmpegImpl* obj = (AudioEncoderFFmpegImpl *) ptr;
    obj->Encode();
    pthread_exit(0);
    return 0;
}
